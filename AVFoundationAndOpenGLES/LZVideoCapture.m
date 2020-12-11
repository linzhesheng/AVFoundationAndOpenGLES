//
//  LZVideoCapture.m
//  AVFoundationAndOpenGLES
//
//  Created by linzhesheng on 2020/11/1.
//

#import "LZVideoCapture.h"

@interface LZVideoCapture()<AVCaptureVideoDataOutputSampleBufferDelegate>

//是否进行
@property (nonatomic, assign) BOOL isRunning;
//会话
@property (nonatomic, strong) AVCaptureSession *captureSession;

@property (nonatomic, strong) dispatch_queue_t captureQueue;
//当前使用的视频设备
@property (nonatomic, weak) AVCaptureDeviceInput *videoInputDevice;
//前后摄像头
@property (nonatomic, strong) AVCaptureDeviceInput *frontCamera;
@property (nonatomic, strong) AVCaptureDeviceInput *backCamera;
//输出数据接收
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic, strong) AVCaptureConnection *videoConnection;

@end

@implementation LZVideoCapture

- (instancetype)init {
    if (self = [super init]) {
        [self setup];
    }
    return self;
}

- (void)setup {
    //所有video设备
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    //前置摄像头
    self.frontCamera = [AVCaptureDeviceInput deviceInputWithDevice:videoDevices.lastObject error:nil];
    self.backCamera = [AVCaptureDeviceInput deviceInputWithDevice:videoDevices.firstObject error:nil];
    //设置当前设备为前置
    self.videoInputDevice = self.backCamera;
    //视频输出
    self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.videoDataOutput setSampleBufferDelegate:self queue:self.captureQueue];
    // 丢弃延迟的视频帧
    self.videoDataOutput.alwaysDiscardsLateVideoFrames = YES;
    // 指定像素的输出格式
    self.videoDataOutput.videoSettings = @{
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
    };
    //配置
    [self.captureSession beginConfiguration];
    if ([self.captureSession canAddInput:self.videoInputDevice]) {
        [self.captureSession addInput:self.videoInputDevice];
    }
    if([self.captureSession canAddOutput:self.videoDataOutput]){
        [self.captureSession addOutput:self.videoDataOutput];
    }
    // 设置分辨率
    [self setVideoPreset];
    [self.captureSession commitConfiguration];
    
    self.videoConnection = [self.videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    //设置视频输出方向
    self.videoConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
    // 设置fps
    [self updateFps:30];
}

// 开始
- (void)start {
    if (!self.isRunning) {
        [self checkCameraAuthorWithCompletion:^(BOOL granted) {
            if (granted) {
                self.isRunning = YES;
                [self.captureSession startRunning];
            }
        }];
    }
}

// 结束
- (void)stop {
    if (self.isRunning) {
        self.isRunning = NO;
        [self.captureSession stopRunning];
    }
}

// 切换摄像头
- (void)changeCamera {
    [self.captureSession beginConfiguration];
    [self.captureSession removeInput:self.videoInputDevice];
    if ([self.videoInputDevice isEqual: self.frontCamera]) {
        self.videoInputDevice = self.backCamera;
    }else{
        self.videoInputDevice = self.frontCamera;
    }
    [self.captureSession addInput:self.videoInputDevice];
    [self.captureSession commitConfiguration];
}

// 摄像头授权 0 ：未授权 1:已授权 -1：拒绝
- (void)checkCameraAuthorWithCompletion:(void (^)(BOOL granted))completion {
    AVAuthorizationStatus videoStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    switch (videoStatus) {
        case AVAuthorizationStatusNotDetermined://第一次
        {
            //    请求授权
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                completion(granted);
            }];
            break;
        }
        case AVAuthorizationStatusAuthorized://已授权
        {
            completion(YES);
            break;
        }
            
        default:
        {
            completion(NO);
            break;
        }
    }
}

// 设置分辨率
- (void)setVideoPreset{
    if ([self.captureSession canSetSessionPreset:AVCaptureSessionPreset1920x1080])  {
        self.captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;
        _witdh = 1080; _height = 1920;
    }else if ([self.captureSession canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
        self.captureSession.sessionPreset = AVCaptureSessionPreset1280x720;
        _witdh = 720; _height = 1280;
    }else{
        self.captureSession.sessionPreset = AVCaptureSessionPreset640x480;
        _witdh = 480; _height = 640;
    }
}

// 设置fps
-(void)updateFps:(NSInteger) fps{
    //获取当前capture设备
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    
    //遍历所有设备（前后摄像头）
    for (AVCaptureDevice *vDevice in videoDevices) {
        //获取当前支持的最大fps
        float maxRate = [(AVFrameRateRange *)[vDevice.activeFormat.videoSupportedFrameRateRanges objectAtIndex:0] maxFrameRate];
        //如果想要设置的fps小于或等于做大fps，就进行修改
        if (maxRate >= fps) {
            //实际修改fps的代码
            if ([vDevice lockForConfiguration:NULL]) {
                vDevice.activeVideoMinFrameDuration = CMTimeMake(10, (int)(fps * 10));
                vDevice.activeVideoMaxFrameDuration = vDevice.activeVideoMinFrameDuration;
                [vDevice unlockForConfiguration];
            }
        }
    }
}

- (AVCaptureSession *)captureSession{
    if (!_captureSession) {
        _captureSession = [[AVCaptureSession alloc] init];
    }
    return _captureSession;
}
- (dispatch_queue_t)captureQueue{
    if (!_captureQueue) {
        _captureQueue = dispatch_queue_create("TMCapture Queue", NULL);
    }
    return _captureQueue;
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    [self.delegate captureSampleBuffer:sampleBuffer];
}

@end
