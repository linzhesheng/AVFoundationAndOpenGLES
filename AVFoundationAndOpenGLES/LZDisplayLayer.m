//
//  LZDisplayLayer.m
//  AVFoundationAndOpenGLES
//
//  Created by linzhesheng on 2020/11/1.
//

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#import "LZDisplayLayer.h"
#include <AVFoundation/AVFoundation.h>
#import <UIKit/UIScreen.h>
#include <OpenGLES/EAGL.h>
#include <OpenGLES/ES2/gl.h>
#include <OpenGLES/ES2/glext.h>

enum
{
    UNIFORM_Y,
    UNIFORM_UV,
    UNIFORM_COLOR_CONVERSION_MATRIX,
    UNIFORM_TIME,
    NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

// YUV->RGB
// 颜色转换常量（yuv到rgb），包括从16-235/16-240（视频范围）进行调整
static const GLfloat kColorConversion601[] = {
    1.164,  1.164, 1.164,
    0.0, -0.392, 2.017,
    1.596, -0.813,   0.0,
};

// BT.709, 这是高清电视的标准
static const GLfloat kColorConversion709[] = {
    1.164,  1.164, 1.164,
    0.0, -0.213, 2.112,
    1.793, -0.533,   0.0,
};

static GLuint programArr[] = {0, 0, 0, 0};


@interface LZDisplayLayer()

{
    // 渲染缓冲区宽度
    GLint _backingWidth;
    // 渲染缓冲区高度
    GLint _backingHeight;
    // 上下文
    EAGLContext *_context;
    /*
     YUV分为2个YUV视频帧分为亮度和色度两个纹理，
     分别用GL_LUMINANCE格式和GL_LUMINANCE_ALPHA格式读取。
     */
    CVOpenGLESTextureRef _lumaTexture;
    CVOpenGLESTextureRef _chromaTexture;
    
    // 帧缓存区
    GLuint _frameBufferHandle;
    // 颜色缓存区
    GLuint _colorBufferHandle;
    
    // 选择颜色通道
    const GLfloat *_preferredConversion;
    // 纹理缓冲区
    CVOpenGLESTextureCacheRef _videoTextureCache;
}

// 起始时间，用于滤镜特效的计算
@property(nonatomic, strong) NSDate *startDate;
// 所有自定义shader
@property(nonatomic, assign) GLuint *program;
// 使用中的shader
@property(nonatomic, assign) GLuint usingProgram;
// 自定义shader数目
@property(nonatomic, assign) int programNumber;

@end

@implementation LZDisplayLayer

- (void)displayWithPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    //获取视频帧的宽与高
    int frameWidth = (int)CVPixelBufferGetWidth(pixelBuffer);
    int frameHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
    
    //显示_pixelBuffer
    [self displayPixelBuffer:pixelBuffer width:frameWidth height:frameHeight];
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super init];
    if (self) {
        self.contentsScale = [[UIScreen mainScreen] scale];
        // 一个布尔值，指示层是否包含完全不透明的内容.默认为NO
        self.opaque = YES;
       
        // kEAGLDrawablePropertyRetainedBacking指定可绘制表面在显示后是否保留其内容的键.默认为NO.
        self.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking :[NSNumber numberWithBool:YES]};
        // 设置layer图层frame
        self.frame = frame;
        
        // 设置绘制框架的上下文.
        _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        if (!_context) {
            return nil;
        }
        
        // 将默认转换设置为BT.709，这是HDTV的标准
        _preferredConversion = kColorConversion709;
        
        self.startDate = [NSDate date];
        
        self.program = programArr;
        
        self.useProgram = 0;
        
        [self setupGL];
    }
    
    return self;
}

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer width:(uint32_t)frameWidth height:(uint32_t)frameHeight
{
    if (!_context || ![EAGLContext setCurrentContext:_context]) {
        return;
    }
    
    if(pixelBuffer == NULL) {
        NSLog(@"Pixel buffer is null");
        return;
    }
    
    // 清理纹理
    [self cleanUpTextures];
    // 清理缓存
    CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
    

    // 返回像素缓冲区的平面数
    size_t planeCount = CVPixelBufferGetPlaneCount(pixelBuffer);
    
    /*
     使用像素缓冲区的颜色附件确定适当的颜色转换矩阵.
     参数1: 像素缓存区
     参数2: kCVImageBufferYCbCrMatrixKey  YCbCr->RGB
     参数3: 附件模式,NULL
     */
    CFTypeRef colorAttachments = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
    
    // 将一个字符串中的字符范围与另一个字符串中的字符范围进行比较
    /*
     参数1:theString1,用于比较的第一个字符串
     参数2:theString2,用于比较的第二个字符串。
     参数3:rangeToCompare,要比较的字符范围。要使用整个字符串，请传递范围或使用。指定的范围不得超过字符串的长度
     */
    if (CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == kCFCompareEqualTo) {
        _preferredConversion = kColorConversion601;
    }
    else {
        _preferredConversion = kColorConversion709;
    }
    
    
    /*
     从像素缓存区pixelBuffer创建Y和UV纹理,这些纹理会被绘制在帧缓存区的Y平面上.
     */
    
    // 激活纹理
    glActiveTexture(GL_TEXTURE0);
    
    // 创建亮度纹理-Y纹理
    /*
     CVOpenGLESTextureCacheCreateTextureFromImage
     功能:根据CVImageBuffer创建CVOpenGlESTexture 纹理对象
     参数1: 内存分配器,kCFAllocatorDefault
     参数2: 纹理缓存.纹理缓存将管理纹理的纹理缓存对象
     参数3: sourceImage.
     参数4: 纹理属性.默认给NULL
     参数5: 目标纹理,GL_TEXTURE_2D
     参数6: 指定纹理中颜色组件的数量(GL_RGBA, GL_LUMINANCE, GL_RGBA8_OES, GL_RG, and GL_RED (NOTE: 在 GLES3 使用 GL_R8 替代 GL_RED).)
     参数7: 帧宽度
     参数8: 帧高度
     参数9: 格式指定像素数据的格式
     参数10: 指定像素数据的数据类型,GL_UNSIGNED_BYTE
     参数11: planeIndex
     参数12: 纹理输出新创建的纹理对象将放置在此处。
     */
    CVReturn err;
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       _videoTextureCache,
                                                       pixelBuffer,
                                                       NULL,
                                                       GL_TEXTURE_2D,
                                                       GL_RED_EXT,
                                                       frameWidth,
                                                       frameHeight,
                                                       GL_RED_EXT,
                                                       GL_UNSIGNED_BYTE,
                                                       0,
                                                       &_lumaTexture);
    if (err) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
    }
    
    // 配置亮度纹理属性
    // 绑定纹理.
    glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
    // 配置纹理放大/缩小过滤方式以及纹理围绕S/T环绕方式
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    // 如果颜色通道个数>1,则除了Y还有UV-Plane.
    if(planeCount == 2) {
        // 激活UV-plane纹理
        glActiveTexture(GL_TEXTURE1);
        // 创建UV-plane纹理
        /*
         CVOpenGLESTextureCacheCreateTextureFromImage
         功能:根据CVImageBuffer创建CVOpenGlESTexture 纹理对象
         参数1: 内存分配器,kCFAllocatorDefault
         参数2: 纹理缓存.纹理缓存将管理纹理的纹理缓存对象
         参数3: sourceImage.
         参数4: 纹理属性.默认给NULL
         参数5: 目标纹理,GL_TEXTURE_2D
         参数6: 指定纹理中颜色组件的数量(GL_RGBA, GL_LUMINANCE, GL_RGBA8_OES, GL_RG, and GL_RED (NOTE: 在 GLES3 使用 GL_R8 替代 GL_RED).)
         参数7: 帧宽度
         参数8: 帧高度
         参数9: 格式指定像素数据的格式
         参数10: 指定像素数据的数据类型,GL_UNSIGNED_BYTE
         参数11: planeIndex
         参数12: 纹理输出新创建的纹理对象将放置在此处。
         */
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_RG_EXT,
                                                           frameWidth / 2,
                                                           frameHeight / 2,
                                                           GL_RG_EXT,
                                                           GL_UNSIGNED_BYTE,
                                                           1,
                                                           &_chromaTexture);
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        // 绑定纹理
        glBindTexture(CVOpenGLESTextureGetTarget(_chromaTexture), CVOpenGLESTextureGetName(_chromaTexture));
        // 配置纹理放大/缩小过滤方式以及纹理围绕S/T环绕方式
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
    
    // 绑定帧缓存区
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
    
    // 设置视口.
    glViewport(0, 0, _backingWidth, _backingHeight);
    
    // 清理屏幕
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    
    // 使用shaderProgram
    glUseProgram(self.program[self.useProgram]);
    self.usingProgram = self.program[self.useProgram];
    
    // 获取uniform的位置
    // Y亮度纹理
    uniforms[UNIFORM_Y] = glGetUniformLocation(self.usingProgram, "SamplerY");
    // UV色量纹理
    uniforms[UNIFORM_UV] = glGetUniformLocation(self.usingProgram, "SamplerUV");
    // YUV->RGB
    uniforms[UNIFORM_COLOR_CONVERSION_MATRIX] = glGetUniformLocation(self.usingProgram, "colorConversionMatrix");
    // 时间差
    uniforms[UNIFORM_TIME] = glGetUniformLocation(self.usingProgram, "Time");
    
    glUniform1i(uniforms[UNIFORM_Y], 0);
    glUniform1i(uniforms[UNIFORM_UV], 1);
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
    
    //传递Uniform属性到shader
    //UNIFORM_COLOR_CONVERSION_MATRIX YUV->RGB颜色矩阵
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
    
    
    // 根据视频的方向和纵横比设置四边形顶点
    CGRect viewBounds = self.bounds;
    CGSize contentSize = CGSizeMake(frameWidth, frameHeight);
    
    /*
     AVMakeRectWithAspectRatioInsideRect
     功能: 返回一个按比例缩放的CGRect，该CGRect保持由边界CGRect内的CGSize指定的纵横比
     参数1:希望保持的宽高比或纵横比
     参数2:填充的rect
     */
    CGRect vertexSamplingRect = AVMakeRectWithAspectRatioInsideRect(contentSize, viewBounds);
    
    // 计算四边形坐标以将帧绘制到其中
    CGSize normalizedSamplingSize = CGSizeMake(0.0, 0.0);
    CGSize cropScaleAmount = CGSizeMake(vertexSamplingRect.size.width/viewBounds.size.width,vertexSamplingRect.size.height/viewBounds.size.height);
    if (cropScaleAmount.width > cropScaleAmount.height) {
        normalizedSamplingSize.width = 1.0;
        normalizedSamplingSize.height = cropScaleAmount.height/cropScaleAmount.width;
    }
    else {
        normalizedSamplingSize.width = cropScaleAmount.width/cropScaleAmount.height;
        normalizedSamplingSize.height = 1.0;;
    }
    
    /*
     四顶点数据定义了绘制像素缓冲区的二维平面区域。
     使用（-1，-1）和（1,1）分别作为左下角和右上角坐标形成的顶点数据覆盖整个屏幕。
     */
    GLfloat quadVertexData [] = {
        -1 * normalizedSamplingSize.width, -1 * normalizedSamplingSize.height,
        normalizedSamplingSize.width, -1 * normalizedSamplingSize.height,
        -1 * normalizedSamplingSize.width, normalizedSamplingSize.height,
        normalizedSamplingSize.width, normalizedSamplingSize.height,
    };
    
    // 更新属性值.
    // 坐标数据
    int position = glGetAttribLocation(self.usingProgram, "position");
    glVertexAttribPointer(position, 2, GL_FLOAT, 0, 0, quadVertexData);
    glEnableVertexAttribArray(position);
    
    /*
     纹理顶点的设置使我们垂直翻转纹理。这使得我们的左上角原点缓冲区匹配OpenGL的左下角纹理坐标系
     */
    CGRect textureSamplingRect = CGRectMake(0, 0, 1, 1);
    GLfloat quadTextureData[] =  {
        CGRectGetMinX(textureSamplingRect), CGRectGetMaxY(textureSamplingRect),
        CGRectGetMaxX(textureSamplingRect), CGRectGetMaxY(textureSamplingRect),
        CGRectGetMinX(textureSamplingRect), CGRectGetMinY(textureSamplingRect),
        CGRectGetMaxX(textureSamplingRect), CGRectGetMinY(textureSamplingRect)
    };
    
    // 更新纹理坐标属性值
    int texCoord = glGetAttribLocation(self.usingProgram, "texCoord");
    glVertexAttribPointer(texCoord, 2, GL_FLOAT, 0, 0, quadTextureData);
    glEnableVertexAttribArray(texCoord);
    
    // 传入当前时间与绘制开始时间的时间差
    NSTimeInterval time = [[NSDate date] timeIntervalSinceDate:self.startDate];
    glUniform1f(uniforms[UNIFORM_TIME], time);
    
    // 绘制图形
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    // 绑定渲染缓存区
    glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    // 显示到屏幕
    [_context presentRenderbuffer:GL_RENDERBUFFER];
    
    
}

// OpenGL 相关设置
- (void)setupGL
{
    if (!_context || ![EAGLContext setCurrentContext:_context]) {
        return;
    }
    
    // 取消深度测试
    glDisable(GL_DEPTH_TEST);
    
    // 创建buffer
    [self createBuffers];
    
    // 加载shaders 着色器
    [self loadShaders];
    
    /*
     CVOpenGLESTextureCacheCreate
     功能:   创建 CVOpenGLESTextureCacheRef 创建新的纹理缓存
     参数1:  kCFAllocatorDefault默认内存分配器.
     参数2:  NULL
     参数3:  EAGLContext  图形上下文
     参数4:  NULL
     参数5:  新创建的纹理缓存
     @result kCVReturnSuccess
     */
    CVReturn err;
    err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_videoTextureCache);
    if (err != noErr) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
        return;
    }

}

- (void)createBuffers
{
    // 创建帧缓存区
    glGenFramebuffers(1, &_frameBufferHandle);
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
    
    // 创建color缓存区
    glGenRenderbuffers(1, &_colorBufferHandle);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    
    // 绑定渲染缓存区
    [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:self];
    
    // 得到渲染缓存区的尺寸
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);
    
    // 绑定renderBuffer到FrameBuffer
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorBufferHandle);
    
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
    }
}

// 释放帧缓存区与渲染缓存区
- (void) releaseBuffers
{
    if(_frameBufferHandle) {
        glDeleteFramebuffers(1, &_frameBufferHandle);
        _frameBufferHandle = 0;
    }
    
    if(_colorBufferHandle) {
        glDeleteRenderbuffers(1, &_colorBufferHandle);
        _colorBufferHandle = 0;
    }
}

// 清理纹理(Y纹理,UV纹理)
- (void) cleanUpTextures
{
    if (_lumaTexture) {
        CFRelease(_lumaTexture);
        _lumaTexture = NULL;
    }
    
    if (_chromaTexture) {
        CFRelease(_chromaTexture);
        _chromaTexture = NULL;
    }
}

- (void)dealloc
{
    if (!_context || ![EAGLContext setCurrentContext:_context]) {
        return;
    }
    
    [self cleanUpTextures];
    
    [self releaseBuffers];
    
    if(_videoTextureCache) {
        CFRelease(_videoTextureCache);
    }
    
    if(_context) {
        _context = nil;
    }
    
    for (int i = 0; i < self.programNumber; i++) {
        glDeleteProgram(self.program[i]);
    }
}

#pragma mark - 自定义shader编译和链接
- (void)loadShaders
{
    for (int i = 0; i < self.programNumber; i++) {
        switch (i) {
            case 0:
                self.program[0] = [self programWithShaderName:@"Vertigo"];
                break;
            case 1:
                self.program[1] = [self programWithShaderName:@"Rag"];
                break;
            case 2:
                self.program[2] = [self programWithShaderName:@"Shake"];
                break;
            case 3:
                self.program[3] = [self programWithShaderName:@"Mosaic"];
            default:
                break;
        }
    }
}

- (GLuint)programWithShaderName:(NSString *)shaderName {
    //1. 编译顶点着色器/片元着色器
    GLuint vertexShader = [self compileShaderWithName:@"Vertex" type:GL_VERTEX_SHADER];
    GLuint fragmentShader = [self compileShaderWithName:shaderName type:GL_FRAGMENT_SHADER];
    
    //2. 将顶点/片元附着到program
    GLuint program = glCreateProgram();
    glAttachShader(program, vertexShader);
    glAttachShader(program, fragmentShader);
    
    //3.linkProgram
    glLinkProgram(program);
    
    //4.检查是否link成功
    GLint linkSuccess;
    glGetProgramiv(program, GL_LINK_STATUS, &linkSuccess);
    if (linkSuccess == GL_FALSE) {
        GLchar messages[256];
        glGetProgramInfoLog(program, sizeof(messages), 0, &messages[0]);
        NSString *messageString = [NSString stringWithUTF8String:messages];
        NSAssert(NO, @"program链接失败：%@", messageString);
        exit(1);
    }
    //5.返回program
    return program;
}

//编译shader代码
- (GLuint)compileShaderWithName:(NSString *)name type:(GLenum)shaderType {
    
    //1.获取shader 路径
    NSString *shaderPath = [[NSBundle mainBundle] pathForResource:name ofType:shaderType == GL_VERTEX_SHADER ? @"vsh" : @"fsh"];
    NSError *error;
    NSString *shaderString = [NSString stringWithContentsOfFile:shaderPath encoding:NSUTF8StringEncoding error:&error];
    if (!shaderString) {
        NSAssert(NO, @"读取shader失败");
        exit(1);
    }
    
    //2. 创建shader->根据shaderType
    GLuint shader = glCreateShader(shaderType);
    
    //3.获取shader source
    const char *shaderStringUTF8 = [shaderString UTF8String];
    int shaderStringLength = (int)[shaderString length];
    glShaderSource(shader, 1, &shaderStringUTF8, &shaderStringLength);
    
    //4.编译shader
    glCompileShader(shader);
    
    //5.查看编译是否成功
    GLint compileSuccess;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compileSuccess);
    if (compileSuccess == GL_FALSE) {
        GLchar messages[256];
        glGetShaderInfoLog(shader, sizeof(messages), 0, &messages[0]);
        NSString *messageString = [NSString stringWithUTF8String:messages];
        NSAssert(NO, @"shader编译失败：%@", messageString);
        exit(1);
    }
    //6.返回shader
    return shader;
}

- (BOOL)validateProgram:(GLuint)prog
{
    GLint logLength, status;
    
    glValidateProgram(prog);
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

- (int)programNumber {
    return 4;
}

@end

#pragma clang diagnostic pop
