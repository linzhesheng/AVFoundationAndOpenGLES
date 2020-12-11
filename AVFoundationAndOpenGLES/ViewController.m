//
//  ViewController.m
//  AVFoundationAndOpenGLES
//
//  Created by linzhesheng on 2020/11/1.
//

#import "ViewController.h"
#import "LZVideoCapture.h"
#import "LZDisplayLayer.h"

@interface ViewController ()<LZVideoCaptureDelegate>

@property (nonatomic, strong) AVCaptureVideoPreviewLayer *preLayer;
@property (nonatomic, strong) LZVideoCapture *videoCapture;
@property (nonatomic, strong) LZDisplayLayer *displayLayer;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.displayLayer = [[LZDisplayLayer alloc] initWithFrame:CGRectMake(0, 80, self.view.bounds.size.width, self.view.bounds.size.height - 80)];
    [self.view.layer addSublayer:self.displayLayer];

    self.videoCapture = [LZVideoCapture new];
    self.videoCapture.delegate = self;
    [self.videoCapture start];
    
}

- (IBAction)clickVertigoButton:(id)sender {
    self.displayLayer.useProgram = LZProgramTypeVertigo;
}

- (IBAction)clickRagButton:(id)sender {
    self.displayLayer.useProgram = LZProgramTypeRag;
}

- (IBAction)clickShakeButton:(id)sender {
    self.displayLayer.useProgram = LZProgramTypeShake;
}

- (IBAction)clickMosaicButton:(id)sender {
    self.displayLayer.useProgram = LZProgramTypeMosaic;
}


- (void)test {
    self.videoCapture = [LZVideoCapture new];
    self.preLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.videoCapture.captureSession];
    self.preLayer.frame = CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height);
    self.preLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer addSublayer:self.preLayer];
    [self.videoCapture start];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (sampleBuffer) {
        [self.displayLayer displayWithPixelBuffer:CMSampleBufferGetImageBuffer(sampleBuffer)];
    }
}

@end
