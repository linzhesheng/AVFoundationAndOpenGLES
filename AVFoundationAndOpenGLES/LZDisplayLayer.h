//
//  LZDisplayLayer.h
//  AVFoundationAndOpenGLES
//
//  Created by linzhesheng on 2020/11/1.
//

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#import <QuartzCore/QuartzCore.h>
#include <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LZProgramType) {
    LZProgramTypeVertigo, // 幻影
    LZProgramTypeRag, // 局部模糊
    LZProgramTypeShake, // 抖动
    LZProgramTypeMosaic // 马赛克
};

@interface LZDisplayLayer : CAEAGLLayer

// 使用哪一种特效
@property(nonatomic, assign) LZProgramType useProgram;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)displayWithPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end

NS_ASSUME_NONNULL_END

#pragma clang diagnostic pop
