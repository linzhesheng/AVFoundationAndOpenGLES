//
//  LZVideoCapture.h
//  AVFoundationAndOpenGLES
//
//  Created by linzhesheng on 2020/11/1.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol LZVideoCaptureDelegate <NSObject>

- (void)captureSampleBuffer:(CMSampleBufferRef)sampleBuffer;

@end

@interface LZVideoCapture : NSObject

@property (nonatomic, weak) id<LZVideoCaptureDelegate> delegate;
//会话
@property (nonatomic, strong, readonly) AVCaptureSession *captureSession;
// 捕获视频的宽
@property (nonatomic, assign, readonly) NSUInteger witdh;
// 捕获视频的高
@property (nonatomic, assign, readonly) NSUInteger height;

// 开始
- (void)start;
// 结束
- (void)stop;
// 切换摄像头
- (void)changeCamera;

@end

NS_ASSUME_NONNULL_END
