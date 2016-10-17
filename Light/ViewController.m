//
//  ViewController.m
//  Light
//
//  Created by Karl Faust on 3/16/16.
//  Copyright © 2016 company. All rights reserved.
//

#import "ViewController.h"
#import "TimePicker.h"
//@import AVFoundation;
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "SCListener.h"
#import <Foundation/Foundation.h>
#import "AppDelegate.h"
@import CoreAudio;
@import CoreLocation;
@import MapKit;

#define INERTIA_STEP 20
#define ALARM_HOUR @"hour"
#define ALARM_MIN @"min"

#define ALARM_ON @"alarm on"
#define WAVE_ON @"wave on"
#define CLAP_ON @"clap on"
#define LIGHTALARM_ON @"light alarm on"
#define ENABLE_TIME 1800

#define FLASH_LEVEL @"flash light level" //origin flash light level

@interface ViewController () <TimePickerDelegate, AVAudioPlayerDelegate, UIScrollViewDelegate, CLLocationManagerDelegate> {
    
    BOOL isFirst;
    AVCaptureDevice *myAVCaptureDevice;
    
    CGPoint oldPoint;//indicating the new point for cycle button
    
    CGPoint minPoint;
    CGPoint maxPoint;
    
    CGFloat r;
    CGFloat r1;
    
    BOOL flashOn;//
    
    BOOL clapOn;
    BOOL waveOn;
    BOOL lightAlarmOn;
    BOOL alarmOn;
    
    CGFloat angle;
    CGFloat myLevel;//indicating whether flashlight level
    
    NSMutableArray *backgroundColors;
    
    NSDate *alarmDate;
    NSInteger hour;
    NSInteger minute;
    
    TimePicker *timePicker;//
    
    NSTimer *timer;//counting time for alarm
    NSInteger totalCount;
    
    NSInteger interval; //indicating the differnent of timezone
    
    BOOL isChangingTime;
    
    //listing mic audio
    NSTimer *listenTimer;
    AVAudioRecorder *recorder;
    BOOL f1;// First Peak Flag: If it is claping sound, then Yes
    BOOL f2;// Second Peak Flag: If it is claping sound, then Yes
    
    //wink flag
    BOOL isIncrease;
    
    //Alert Sound
    AVAudioPlayer *myPlayer;
    
    //alert view controller
//    UIAlertController *alertC;
    BOOL isAlertShown;
    
//    //--battery state
//    UIDeviceBatteryState originBatteryState;
    NSTimer *enableTimer;
    
    BOOL isConnectedCharger;
    
    //tracking current location for background mode
    CLLocationManager *locationManager;
    NSMutableArray<MKPointAnnotation *> * locations;
}

//@property (strong, nonatomic) UIScrollView *baseScrollView;

@property (strong, nonatomic) UIImageView *backgroundImageView;

@property (strong, nonatomic) UIView *baseView;

//First View
@property (strong, nonatomic) UIView *firstView;
@property (strong, nonatomic) UIView *cycleView;
@property (strong, nonatomic) UIImageView *cycleImageV;
@property (strong, nonatomic) UIButton *cycleButton;
@property (strong, nonatomic) UIImageView *pushImageView;
@property (strong, nonatomic) UIButton *upDownButton;
@property (strong, nonatomic) MyLabel *timeLabel;
@property (strong, nonatomic) UIImageView *ringImageView;

//Second View
@property (strong, nonatomic) UIView *secondView;

@property (strong, nonatomic) UISwitch *alarmSwitch;
@property (strong, nonatomic) UISwitch *lightAlarmSwitch;
@property (strong, nonatomic) UISwitch *waveSwitch;
@property (strong, nonatomic) UISwitch *clapSwitch;

@property (strong, nonatomic) UILabel *alarmOnDescriptionLabel;// will show when alarm on enabled

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.

    isFirst = YES;
    
    [self initPositionOfControls];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didlocalNotificationReceived:) name:@"localNotificationReceived" object:nil];
    
    [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];
    [[UIDevice currentDevice] batteryLevel];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkBatteryState) name:UIDeviceBatteryStateDidChangeNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkBatteryState) name:UIDeviceBatteryLevelDidChangeNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(willResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    
    UIDevice *device = [UIDevice currentDevice];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(proximityChanged:) name:UIDeviceProximityStateDidChangeNotification object:device];
    
    [self prepareAlarmAudio];
    
    [self initTrackingLocation];
}

- (void)willResignActive: (NSNotification *)sender {
    
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithFloat:myLevel] forKey:FLASH_LEVEL];
    
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    
    if (isAlertShown) {
        [self stopAlert];
    }
    
    if (recorder) {
        [recorder stop];
        recorder = nil;
    }
    
    if (timer) {
        [timer invalidate];
        timer = nil;
    }
    
    if (listenTimer) {
        [listenTimer invalidate];
        listenTimer = nil;
    }
    
    if (enableTimer) {
        [enableTimer invalidate];
        enableTimer = nil;
    }
}

- (void)didBecomeActive: (NSNotification *)sender {
    
    if ([[NSUserDefaults standardUserDefaults] objectForKey:FLASH_LEVEL]) {
        myLevel = [(NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:FLASH_LEVEL] floatValue];
        [self setFlashLevel:myLevel];
        [self setCycleButtonLocationWithLevel:myLevel];
    }
    
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    
    [self readyListening];
    
    [self countingTime];
    
    [self countingEnableTime];
    
    isConnectedCharger = NO;
    if ([[UIDevice currentDevice] batteryState] != UIDeviceBatteryStateUnplugged && isConnectedCharger == NO) {
        isConnectedCharger = YES;
        [self.pushImageView startAnimating];
    }
}

- (void)readyListening {
    
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    [audioSession setActive:YES error:nil];
    
    //set up the URL for the audio File
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    NSString *str = [documents stringByAppendingPathComponent:@"recordTest.caf"];
    NSURL *url = [NSURL fileURLWithPath:str];
    
    // make a dictionary to hold the recording settings so we can instantiate our AVAudioRecorder
    NSMutableDictionary *recordSettings = [[NSMutableDictionary alloc] init];
    [recordSettings setValue:[NSNumber numberWithInt:kAudioFormatAppleIMA4] forKey:AVFormatIDKey];
    [recordSettings setValue:[NSNumber numberWithInt:44100.0] forKey:AVSampleRateKey];
    [recordSettings setValue:[NSNumber numberWithInt:2] forKey:AVNumberOfChannelsKey];
    [recordSettings setValue:[NSNumber numberWithInt:12800] forKey:AVEncoderBitRateKey];
    [recordSettings setValue:[NSNumber numberWithInt:16] forKey:AVLinearPCMBitDepthKey];
    [recordSettings setValue:[NSNumber numberWithInt:AVAudioQualityMax] forKey:AVEncoderAudioQualityKey];
    
    //declare a variable to store the returned error if we have a problem instantiating our AVAudioRecorder
    NSError *error;
    
    //Instantiate an AVAudioRecorder
    recorder = [[AVAudioRecorder alloc] initWithURL:url settings:recordSettings error:&error];
    
    //If there's an error, print that shit - otherwise, run prepareToRecord and meteringEnabled to turn on metering (must be run in that order)
    if (error) {
        NSLog(@"%@", error.localizedDescription);
    }else{
        [recorder prepareToRecord];
        [recorder setMeteringEnabled:YES];
        
        //start recording
        [recorder record];
        
        f1 = NO;
        f2 = NO;
        //instantiate a timer to be called with whatever frequency we want to grab metering values
        listenTimer = [NSTimer scheduledTimerWithTimeInterval:0.01 target:self selector:@selector(levelTimerCallback) userInfo:nil repeats:YES];
    }
}

- (void)levelTimerCallback {
    //we have to update meters before we can get the metering values
    [recorder updateMeters];
    
    NSLog(@"Peak decibel: %f", [recorder peakPowerForChannel:0]);
    
    if ([recorder peakPowerForChannel:0] < - 100.0) {
        [recorder stop];
        recorder = nil;
        
        [self readyListening];
        
        if (listenTimer) {
            [listenTimer invalidate];
        }
        
        return;
    }
    
    //print to the console if we are beyond a threshold value. Here I've used -7
    if ([recorder peakPowerForChannel:0] > - 0.1) {
        f2 = YES;
    }else {
        f2 = NO;
    }
    
    if (f1 == NO && f2 == YES) {
        if (isAlertShown) {
            [self snooseAlert];
        }else{
            if (clapOn) {
                CGFloat origin = myLevel;
                if (flashOn) {
                    myLevel = 0;
                }else {
                    myLevel = 1;
                }
                [self setPositionFromOrigin:origin toCurrent:myLevel];
                
                [self toggleFlashlight];
            }
        }
    }
    
    f1 = f2;
}

- (void)captureDeviceSubjectArea: (NSNotification *)sender {
    NSLog(@"captureDevice...");
}

- (void)wasConnected: (NSNotification *)sender {
    NSLog(@"wasConnected...");
}

- (void)wasDisconnected: (NSNotification *)sender {
    NSLog(@"wasDisconnected...");
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if (![[NSUserDefaults standardUserDefaults] objectForKey:ALARM_ON]) {
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:NO] forKey:ALARM_ON];
    }
    if (![[NSUserDefaults standardUserDefaults] objectForKey:CLAP_ON]) {
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:NO] forKey:CLAP_ON];
    }
    if (![[NSUserDefaults standardUserDefaults] objectForKey:LIGHTALARM_ON]) {
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:NO] forKey:LIGHTALARM_ON];
    }
    if (![[NSUserDefaults standardUserDefaults] objectForKey:WAVE_ON]) {
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:NO] forKey:WAVE_ON];
    }
    
    
    [self.alarmSwitch setOn:[[[NSUserDefaults standardUserDefaults] objectForKey:ALARM_ON] boolValue]];
    [self.lightAlarmSwitch setOn:[[[NSUserDefaults standardUserDefaults] objectForKey:LIGHTALARM_ON] boolValue]];
    [self.waveSwitch setOn:[[[NSUserDefaults standardUserDefaults] objectForKey:WAVE_ON] boolValue]];
    [self.clapSwitch setOn:[[[NSUserDefaults standardUserDefaults] objectForKey:CLAP_ON] boolValue]];
    
    alarmOn = [[[NSUserDefaults standardUserDefaults] objectForKey:ALARM_ON] boolValue];
    clapOn = [[[NSUserDefaults standardUserDefaults] objectForKey:CLAP_ON] boolValue];
    lightAlarmOn = [[[NSUserDefaults standardUserDefaults] objectForKey:LIGHTALARM_ON] boolValue];
    waveOn = [[[NSUserDefaults standardUserDefaults] objectForKey:WAVE_ON] boolValue];
    
    if ([[NSUserDefaults standardUserDefaults] objectForKey:ALARM_HOUR] && [[NSUserDefaults standardUserDefaults] objectForKey:ALARM_MIN]) {
        hour = [[[NSUserDefaults standardUserDefaults] objectForKey:ALARM_HOUR] integerValue];
        minute = [[[NSUserDefaults standardUserDefaults] objectForKey:ALARM_MIN] integerValue];
        
        if (alarmOn) {
            [self.ringImageView setImage:[UIImage imageNamed:@"ic_ring.png"]];
        }else{
            [self.ringImageView setImage:[UIImage imageNamed:@"ic_ring_off.png"]];
        }
    }else{
        hour = 12;
        minute = 00;
    }
    
    if (waveOn) {
        UIDevice *device = [UIDevice currentDevice];
        device.proximityMonitoringEnabled = YES;
    }
    
    if (lightAlarmOn) {
        [self.alarmOnDescriptionLabel setAlpha:1];
    }else{
        [self.alarmOnDescriptionLabel setAlpha:0];
    }
    
    [timePicker setHour:hour Minute:minute];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    if (!timer) {
        [timer invalidate];
        timer = nil;
    }
    
    if (!listenTimer) {
        [listenTimer invalidate];
        listenTimer = nil;
    }
}

- (void)viewDidLayoutSubviews {

}

//- (void)ge

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - handling local notification

- (void)didlocalNotificationReceived: (UILocalNotification *)sender {
    
    [self showAlertWithString:@"Uplamp is ready"];
    
    [myPlayer play];
    
//    if (timer) {
//        [timer invalidate];
//        timer = nil;
//    }
}

#pragma mark - Background Mode handler

- (void)fetchNewDataWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    completionHandler(UIBackgroundFetchResultNoData);
    completionHandler(UIBackgroundFetchResultNewData);
    completionHandler(UIBackgroundFetchResultFailed);
}

- (void)initTrackingLocation {
    locations = [[NSMutableArray alloc] init];
    
    locationManager = [[CLLocationManager alloc] init];
    [locationManager setDesiredAccuracy:kCLLocationAccuracyBest];
    [locationManager setDelegate:self];
    [locationManager requestAlwaysAuthorization];
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    
}

#pragma mark - 

- (void)snooseAlert {
    if (myPlayer) {
        [myPlayer stop];
    }
    
//    double delayInSeconds = 300.0;
//    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
//    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
//        [self showAlertWithString:@"Uplamp is ready!"];
//        
//        [myPlayer play];
//    });
    
    //--
    [self stopAlert];
//    [self dismissAlarmAlert];
    
    [self.ringImageView stopAnimating];
    
    NSDate *date = [NSDate date];
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *todayComps = [calendar components:(NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear | NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date];
    todayComps.minute += 6;
    alarmDate = [calendar dateFromComponents:todayComps];
    
    [self scheduleLocalNotificationWithDate:alarmDate];
}

- (void)prepareAlarmAudio {
    NSURL *url = [NSURL fileURLWithPath:[[NSBundle mainBundle]
                                         pathForResource:@"radar"
                                         ofType:@"mp3"]];
    NSError *sessionError = nil;
    myPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:nil];
    //    [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayback error:&sessionError]; //AVAudioSessionCategoryPlayAndRecord
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers  error:&sessionError];
    [[AVAudioSession sharedInstance] setActive:YES error:&sessionError];
    
    [myPlayer prepareToPlay];
    [myPlayer setDelegate:self];
    myPlayer.numberOfLoops = -1;
    [myPlayer setVolume:10.0000];
}

- (void)showAlertWithString: (NSString *)msg {
    
    totalCount = ENABLE_TIME;
    
    if (lightAlarmOn) {
        flashOn = NO;
        if (myLevel < 0.2) {
            myLevel = 1.0;
        }
        [self toggleFlashlight];
    }
//    isAlertShown = NO;
    
//    alertC = [UIAlertController alertControllerWithTitle:@"" message:msg preferredStyle:UIAlertControllerStyleActionSheet];
//    UIAlertAction *snoose = [UIAlertAction actionWithTitle:@"Snoose" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    
//        [self snooseAlert];
//    }];
    
//    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
//        if (myPlayer) {
//            [myPlayer stop];
//        }
    
//        [self dismissAlarmAlert];
    
//        [self.ringImageView stopAnimating];
//    }];
    
//    [alertC addAction:snoose];
//    [alertC addAction:ok];
//    [self presentViewController:alertC animated:YES completion:nil];
    isAlertShown = YES;
    
    [self.ringImageView startAnimating];
    
    if (isFirst == NO) {
        [self upBaseViewWithDuration:0.3 delay:0 animationStep:INERTIA_STEP];
    }
}

- (void)stopAlert {//not snoozing
    isAlertShown = NO;
    
    if (myPlayer) {
        [myPlayer stop];
    }
    [self.ringImageView stopAnimating];
    
    if (lightAlarmOn) {
        flashOn = YES;
        [self toggleFlashlight];
    }
    
    [[UIApplication sharedApplication] cancelAllLocalNotifications];
}

//- (void)dismissAlarmAlert {
//    [alertC dismissViewControllerAnimated:YES completion:nil];
//    isAlertShown = NO;
//    
//    if (lightAlarmOn) {
//        flashOn = YES;
//        [self toggleFlashlight];
//    }
//}

- (void)showChargerAlertWithString: (NSString *)msg {
    totalCount = ENABLE_TIME;
    UIAlertController *alertChargerC = [UIAlertController alertControllerWithTitle:@"" message:msg preferredStyle:UIAlertControllerStyleAlert];

    [self presentViewController:alertChargerC animated:YES completion:nil];
    
    double delayInSeconds = 1.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [alertChargerC dismissViewControllerAnimated:YES completion:nil];
    });
}

- (void)showTestAlertWithString: (NSString *)msg {

    UIAlertController *alertChargerC = [UIAlertController alertControllerWithTitle:@"" message:msg preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [alertChargerC dismissViewControllerAnimated:YES completion:nil];
    }];
    
    [alertChargerC addAction:ok];
    
    [self presentViewController:alertChargerC animated:YES completion:nil];
}

#pragma mark - Motion Handling

- (void)motionBegan:(UIEventSubtype)motion withEvent:(UIEvent *)event {
//    NSLog(@"Motion Began....");
//    [self toggleFlashlight];
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
//    NSLog(@"Motion Ending....");
}

- (void)motionCancelled:(UIEventSubtype)motion withEvent:(UIEvent *)event {
//    NSLog(@"Motioin Cancelled....");
}

#pragma mark - My Event

- (void)scheduleLocalNotificationWithDate:(NSDate *)date {
    
    [[UIApplication sharedApplication] cancelAllLocalNotifications];
    
    AppDelegate *del = (AppDelegate *)([UIApplication sharedApplication].delegate);
    UILocalNotification *notification = del.alarmNotification;
    
    NSLog(@"Notification Date: %@", date);
    
    notification.fireDate = date;
    notification.alertBody = @"Uplamp is ready";
//    [notification setAlertAction:@"Alert Action"];
    notification.soundName = @"radar.mp3";
//    notification.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    notification.timeZone = [NSTimeZone localTimeZone];
    
    NSTimeZone *timeZ = [NSTimeZone localTimeZone];
    timeZ = [NSTimeZone defaultTimeZone];
    timeZ = [NSTimeZone systemTimeZone];
    
    notification.repeatInterval = NSCalendarUnitYear;
    
    [notification setApplicationIconBadgeNumber:[[UIApplication sharedApplication] applicationIconBadgeNumber] + 1];
    
    [[UIApplication sharedApplication] scheduleLocalNotification:notification];

//    [notification release];
}

- (void)toggleFlashlight
{
    AVCaptureDevice *flashLight = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if ([flashLight isTorchAvailable] && [flashLight isTorchModeSupported:AVCaptureTorchModeOn])
    {
        BOOL success = [flashLight lockForConfiguration:nil];
        if (success)
        {
            if (flashOn)//[flashLight isTorchActive]
            {
                flashOn = NO;
                [flashLight setTorchMode:AVCaptureTorchModeOff];
                
                [self setPositionFromOrigin:myLevel toCurrent:0];
            }
            else
            {
                flashOn = YES;
                if (myLevel < 0.02) {
                    [flashLight setTorchMode:AVCaptureTorchModeOff];
                }else{
                    [flashLight setTorchModeOnWithLevel:myLevel error:nil];
                }

                [self setPositionFromOrigin:0 toCurrent:myLevel];
            }
            [flashLight unlockForConfiguration];
        }
    }
}

- (void)setFlashLevel: (CGFloat)level {
    
    if (level > 0 && level <= 1) {
        myLevel = level;
    }else{
//        return;
    }

//    [self toggleFlashlight];
    AVCaptureDevice *flashLight = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if ([flashLight isTorchAvailable] && [flashLight isTorchModeSupported:AVCaptureTorchModeOn])
    {
        BOOL success = [flashLight lockForConfiguration:nil];
        if (success)
        {
//            if (flashOn)//[flashLight isTorchActive]
//            {
                if (level < 0.02) {
                    [flashLight setTorchMode:AVCaptureTorchModeOff];
                    flashOn = NO;
                }else{
                    [flashLight setTorchModeOnWithLevel:level error:nil];
                    flashOn = YES;
                }
//            }
            [flashLight unlockForConfiguration];
        }
    }
}

- (void)setAlarmDate {
//    NSString *string = [NSString stringWithFormat:@"%ld:%ld", (long)hour, (long)minute];
//    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
//    NSDateFormatter *timeOnlyFormatter = [[NSDateFormatter alloc] init];
//    [timeOnlyFormatter setLocale:locale];
//    [timeOnlyFormatter setDateFormat:@"HH:mm"];
//    
//    NSDate *date = [timeOnlyFormatter dateFromString:string];
//    NSLog(@"current: %@", date);
//
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    
    NSDate *today = [NSDate date];//[self getLocalDate];
    
    NSDateComponents *todayComps = [calendar components:(NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear) fromDate:today];
    todayComps.hour = hour;
    todayComps.minute = minute;
    
//    NSDateComponents *comps = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:[timeOnlyFormatter dateFromString:string]];
//    comps.day = todayComps.day;
//    comps.month = todayComps.month;
//    comps.year = todayComps.year;
    alarmDate = [calendar dateFromComponents:todayComps];
    NSLog(@"%@", alarmDate);
}

#pragma mark - TimePicker Delegate

- (void)timePickerDidSelectTime:(TimePicker *)picker {
    
    isChangingTime = NO;
    
    hour = picker.hour;
    minute = picker.minute;
    
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInteger:hour] forKey:ALARM_HOUR];
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInteger:minute] forKey:ALARM_MIN];
}

- (void)timePickerDidStartSelection:(TimePicker *)picker {
    totalCount = ENABLE_TIME;
    isChangingTime = YES;
    
    if ([self.alarmSwitch isOn]) {
        [self.alarmSwitch setOn:NO animated:YES];
    }
}

#pragma mark - Switch Event

- (void)clapSwitch: (UISwitch *)sender {
    totalCount = ENABLE_TIME;
    if ([sender isOn]) {
        clapOn = YES;
    }else{
        clapOn = NO;
    }
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:clapOn] forKey:CLAP_ON];
}

- (void)waveSwitch: (UISwitch *)sender {
    totalCount = ENABLE_TIME;
    if ([sender isOn]) {
        waveOn = YES;
        [[UIDevice currentDevice] setProximityMonitoringEnabled:YES];
    }else{
        waveOn = NO;
        [[UIDevice currentDevice] setProximityMonitoringEnabled:NO];
    }
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:waveOn] forKey:WAVE_ON];
}

- (void)lightAlarmSwitch: (UISwitch *)sender {
    totalCount = ENABLE_TIME;
    if ([sender isOn]) {
        lightAlarmOn = YES;
        [self showAlarmOnDescription];
    }else{
        lightAlarmOn = NO;
        [self hideAlarmOnDescription];
    }
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:lightAlarmOn] forKey:LIGHTALARM_ON];
}

- (void)alarmSwitch: (UISwitch *)sender {
    if (isChangingTime) {
        [self.alarmSwitch setOn:NO animated:YES];
        return;
    }
    
    totalCount = ENABLE_TIME;
    if ([sender isOn]) {
        alarmOn = YES;
        [self setAlarmDate];
        [self scheduleLocalNotificationWithDate: alarmDate];
        
        [self.ringImageView setImage:[UIImage imageNamed:@"ic_ring.png"]];
        
        [self countingTime];
    }else{
        alarmOn = NO;
        [self.timeLabel setHidden:NO];
        
        [self.ringImageView setImage:[UIImage imageNamed:@"ic_ring_off.png"]];
        
//        if (timer) {
//            [timer invalidate];
//            timer = nil;
//        }
        
        [[UIApplication sharedApplication] cancelAllLocalNotifications];
        
        if (isAlertShown) {
            [self stopAlert];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:alarmOn] forKey:ALARM_ON];
}

#pragma mark - 

- (void)countingEnableTime {
//    AppDelegate *del = (AppDelegate *)[UIApplication sharedApplication].delegate;

    if (enableTimer) {
        [enableTimer invalidate];
        enableTimer = nil;
    }
    
    totalCount = ENABLE_TIME;
    
    enableTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                             target:self
                                           selector:@selector(subtractEnableTime)
                                           userInfo:nil
                                            repeats:YES];
}

- (void)subtractEnableTime {
    totalCount--;
    
//    AppDelegate *del = (AppDelegate *)[UIApplication sharedApplication].delegate;
    if (isConnectedCharger) {
        totalCount = ENABLE_TIME;
    }
    
    if (totalCount <= 0) {
        [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    }
}

- (void)countingTime {
    
    if (timer) {
        [timer invalidate];
        timer = nil;
    }
    timer = [NSTimer scheduledTimerWithTimeInterval:0.5f
                                             target:self
                                           selector:@selector(subtractTime)
                                           userInfo:nil
                                            repeats:YES];
    
}

- (void)subtractTime {
    
    NSString *hStr = [[NSString alloc] init];
    NSString *mStr = [[NSString alloc] init];
    
    NSDate *destinationDate = [NSDate date];//[self getLocalDate];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:destinationDate];
    
    NSInteger h = components.hour;
    NSInteger m = components.minute;
    
    if (h < 10) {
        hStr = [NSString stringWithFormat:@"0%ld", (long)h];
    }else{
        hStr = [NSString stringWithFormat:@"%ld", (long)h];
    }
    if (m < 10) {
        mStr = [NSString stringWithFormat:@"0%ld", (long)m];
    }else{
        mStr = [NSString stringWithFormat:@"%ld", (long)m];
    }

    [self.timeLabel setText:[NSString stringWithFormat:@"%@:%@", hStr, mStr]];

    if (h <= 12) {
        [[UIScreen mainScreen] setBrightness: 0.1 + 0.9 * ((CGFloat)h * 60.0f + (CGFloat)m) / (12.0 * 60.0)];
    }else{
        [[UIScreen mainScreen] setBrightness: 1.0 - 0.9 * ((CGFloat)(h - 12) * 60.0f + (CGFloat)m) / (12.0 * 60.0)];
    }
//    [[UIScreen mainScreen] setBrightness:0.1];
}

#pragma mark - 

- (void)proximityChanged: (NSNotification *)sender {
    UIDevice *device = [sender object];
    if (!waveOn) {//!flashOn ||
        return;
    }
    
    CGFloat origin = myLevel;
    if ([device proximityState] == YES){
        
        if (myLevel < 0.1) {
            isIncrease = YES;
        }else if (myLevel > 0.9) {
            isIncrease = NO;
        }
        
        if (isIncrease) {
            if (myLevel < 0.3) {
                myLevel = 0.3;
            }else if (myLevel >= 0.3 && myLevel < 0.6) {
                myLevel = 0.6;
            }else if (myLevel >= 0.6) {
                myLevel = 1.0;
                isIncrease = NO;
            }else {
                myLevel = 0.0;
            }
        }else{
            if (myLevel > 0.6) {
                myLevel = 0.6;
            }else if (myLevel <= 0.6 && myLevel > 0.3) {
                myLevel = 0.3;
            }else if (myLevel <= 0.3) {
                myLevel = 0.0;
                isIncrease = YES;
            }else {
                myLevel = 1.0;
            }
        }
        [self setFlashLevel:myLevel];
        
        [self setPositionFromOrigin:origin toCurrent:myLevel];
        NSLog(@"Device is close to user.");
    }else{

        NSLog(@"Device is ~not~ closer to user.");
    }
    
    totalCount = ENABLE_TIME;
}

- (void)checkBatteryState {
    [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];
    
//    AppDelegate *del = (AppDelegate *)[UIApplication sharedApplication].delegate;
    
    if ([[UIDevice currentDevice] batteryState] == UIDeviceBatteryStateUnplugged) {
//        [self showChargerAlertWithString:@"disconnected with battery..."];
        
        isConnectedCharger = NO;
        
        [self.pushImageView stopAnimating];
    }else if(isConnectedCharger == NO) {
        
        isConnectedCharger = YES;
        
        [self.pushImageView startAnimating];
        
        if (isFirst == NO) {
            [self upBaseViewWithDuration:0.3 delay:0 animationStep:INERTIA_STEP];
        }
    }
}

#pragma mark - push Event

- (void)ringButtonTouchUp: (UIButton *)sender {
    if (isAlertShown) {
        [self snooseAlert];
    }
}

- (void)pushView: (UIButton *)sender {
    totalCount = ENABLE_TIME;
    
    if (isAlertShown) {
//        [self stopAlert];
    }
    
    if (isChangingTime) {
        return;
    }
    
    if (isFirst) {
        [self downBaseViewWithDuration:0.3 delay:0 animationStep:INERTIA_STEP];
    }else {
        [self upBaseViewWithDuration:0.3 delay:0 animationStep:INERTIA_STEP];
    }
    
}

- (void)pushUpBaseView: (UISwipeGestureRecognizer *)sender {
    totalCount = ENABLE_TIME;
    if (isChangingTime) {
        return;
    }
//    if (isFirst) {
        [self downBaseViewWithDuration:0.3 delay:0 animationStep:INERTIA_STEP];
//    }else{
//        [self downBaseViewWithDuration:0.3 delay:0 animationStep:INERTIA_STEP];
//    }
}

- (void)pushDownBaseView: (UISwipeGestureRecognizer *)sender {
    totalCount = ENABLE_TIME;
    if (isChangingTime) {
        return;
    }
//    if (!isFirst) {
        [self upBaseViewWithDuration:0.3 delay:0 animationStep:INERTIA_STEP];
//    }else{
//        [self upBaseViewWithDuration:0.3 delay:0 animationStep:INERTIA_STEP];
//    }
}

- (void)downBaseViewWithDuration: (CGFloat)duration delay: (CGFloat)delay animationStep: (CGFloat)inertiaStep {
    [UIView animateWithDuration:duration delay:delay options:UIViewAnimationOptionCurveEaseOut animations:^{
        [self.baseView setFrame:CGRectMake(0, self.view.frame.size.height - self.baseView.frame.size.height - inertiaStep, self.baseView.frame.size.width, self.baseView.frame.size.height)];

        [self.upDownButton setBackgroundImage:[UIImage imageNamed:@"ic_up.png"] forState:UIControlStateNormal];
    } completion:^(BOOL finished) {
        isFirst = NO;
        [UIView animateWithDuration:duration delay:delay options:UIViewAnimationOptionCurveEaseOut animations:^{
            [self.baseView setFrame:CGRectMake(0, self.view.frame.size.height - self.baseView.frame.size.height, self.baseView.frame.size.width, self.baseView.frame.size.height)];

        }completion:^(BOOL finished) {
        }];
    }];
}

- (void)upBaseViewWithDuration: (CGFloat)duration delay: (CGFloat)delay animationStep: (CGFloat)inertiaStep {
    [UIView animateWithDuration:duration delay:delay options:UIViewAnimationOptionCurveEaseOut animations:^{
        
        [self.baseView setFrame:CGRectMake(0, inertiaStep, self.baseView.frame.size.width, self.baseView.frame.size.height)];

        [self.upDownButton setBackgroundImage:[UIImage imageNamed:@"ic_down.png"] forState:UIControlStateNormal];
        
    } completion:^(BOOL finished) {
        
        isFirst = YES;
        
        [UIView animateWithDuration:duration delay:delay options:UIViewAnimationOptionCurveEaseOut animations:^{
            [self.baseView setFrame:CGRectMake(0, 0, self.baseView.frame.size.width, self.baseView.frame.size.height)];

        } completion:^(BOOL finished) {
        }];
    }];
}

#pragma mark - UIScrollView Delegate

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    NSLog(@"DidEndScrollingAnimation...");
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    NSLog(@"DidScroll...");
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    NSLog(@"DidEndDragging...");
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    NSLog(@"WillEndDragging...");
}

#pragma mark - UI Initialization

- (void)setBackgroundColor {
   
    NSDate *destinationDate = [self getLocalDate];
//    NSLog(@"%@ : %@", sourceDate, destinationDate);
    NSCalendar *calendar = [NSCalendar currentCalendar];
//    calendar change
    NSDateComponents *components = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:destinationDate];
    
    [self.view setBackgroundColor:backgroundColors[components.hour]];
}

- (NSDate *)getLocalDate {
    NSDate *sourceDate = [NSDate date];
    
    NSTimeZone *sourceTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    NSTimeZone *destinationTimeZone = [NSTimeZone systemTimeZone];
    
    NSInteger sourceGMTOffset = [sourceTimeZone secondsFromGMTForDate:sourceDate];
    NSInteger destinationGMTOffset = [destinationTimeZone secondsFromGMTForDate:sourceDate];
    interval = destinationGMTOffset - sourceGMTOffset;
    
    NSDate *destinationDate = [[NSDate alloc] initWithTimeInterval:interval sinceDate:sourceDate];
    
    return destinationDate;
}

- (void)addSwipeGestureInBaseView {
    UISwipeGestureRecognizer *swipeGestureUp = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(pushUpBaseView:)];
    swipeGestureUp.direction = UISwipeGestureRecognizerDirectionUp;
    [self.baseView addGestureRecognizer:swipeGestureUp];
    
    UISwipeGestureRecognizer *swipeGestureDown = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(pushDownBaseView:)];
    swipeGestureDown.direction = UISwipeGestureRecognizerDirectionDown;
    [self.baseView addGestureRecognizer:swipeGestureDown];
}

- (void)panForCycleButton: (UIPanGestureRecognizer *)sender {
//    if (!flashOn) {
//        return;
//    }
    
    if ([sender state] == UIGestureRecognizerStateBegan) {
        oldPoint = [sender locationInView:self.cycleView];
//        NSLog(@"%f, %f", oldPoint.x, oldPoint.y);
    }
    
    CGPoint newPoint = [sender locationInView:self.cycleView];
    
    [self setPositionWith:newPoint];
    
    oldPoint = newPoint;
}

- (void)initCycleData {
    CGFloat w = self.cycleView.frame.size.width * 44.0f / 290.0f;
    angle = M_PI / 4;
    
    r = self.cycleView.frame.size.width / 2;
    r1 = (self.cycleView.frame.size.width - w) / 2;
    
    minPoint.x = r1 * cos(M_PI + angle);
    minPoint.y = r1 * sin(M_PI + angle);
    
    maxPoint.x = r1 * cos(- angle);
    maxPoint.y = r1 * sin(- angle);
}

- (void)setPositionWith: (CGPoint)point {

//    CGPoint newPoint;
//    newPoint.x = point.x - r;
//    newPoint.y = r - point.y;
//
//    CGFloat dc = sqrt(newPoint.x * newPoint.x + newPoint.y * newPoint.y);
//    newPoint.x = newPoint.x * r1 / dc;
//    newPoint.y = newPoint.y * r1 / dc;
//    
//    if (newPoint.x < maxPoint.x && newPoint.x > minPoint.x && newPoint.y < maxPoint.y) {
//        return;
//    }
//    
//    CGFloat currentAngle = atan(newPoint.y / newPoint.x);
//
//    if (newPoint.x > 0 && newPoint.y <= 0) {
//        currentAngle = M_PI + angle - currentAngle;
//    }else if (newPoint.x <= 0 && newPoint.y > 0) {
//        currentAngle = angle - currentAngle;
//    }else if (newPoint.x < 0 && newPoint.y <= 0) {
//        currentAngle = angle - currentAngle;
//    }else if (newPoint.x > 0 && newPoint.y > 0) {
//        currentAngle = M_PI + angle - currentAngle;
//    }

    CGFloat originLevel = [self getLevelWithPosition:self.cycleButton.layer.position];
    
    CGFloat currentLevel = [self getLevelWithPosition:point];
    if (currentLevel == -1) {
        return;
    }
    if (currentLevel < 0) {
        currentLevel = 0.01;
    }

    [self setFlashLevel: (CGFloat)currentLevel];
    
//    newPoint.x = r - self.cycleButton.frame.size.width / 2 + newPoint.x;
//    newPoint.y = r - self.cycleButton.frame.size.height / 2 - newPoint.y;
    
//    [self setPositionFromOrigin:originLevel toCurrent:currentLevel];
    
    if (originLevel < currentLevel) {
        for (CGFloat i = originLevel; i <= currentLevel; i = i + 0.01) {
            [self setCycleButtonLocationWithLevel:i];
        }
    }else {
        for (CGFloat i = originLevel; i >= currentLevel; i = i - 0.01) {
            [self setCycleButtonLocationWithLevel:i];
        }
    }
}

- (void)initPositionForCycleButton {
    CGFloat w = self.cycleView.frame.size.width * 44.0f / 290.0f;
    
    CGPoint initPoint;
    initPoint.x = r + minPoint.x - w / 2;
    initPoint.y = r - minPoint.y - w / 2;
    
    [self.cycleButton setFrame:CGRectMake(initPoint.x, initPoint.y, w, w)];
    myLevel = 0;
}

- (void)setCycleButtonLocationWithLevel: (CGFloat)level {
    CGFloat w = self.cycleView.frame.size.width * 44.0f / 290.0f;
    CGFloat a = M_PI * 5 / 4 - level * M_PI * 3 / 2;
    CGPoint point;
    
    point.x = r1 * cos(a);
    point.y = r1 * sin(a);
    
    point.x = r + point.x - w / 2;
    point.y = r - point.y - w / 2;
    
    [self.cycleButton setFrame:CGRectMake(point.x, point.y, self.cycleButton.frame.size.width, self.cycleButton.frame.size.height)];
}

- (void)smoothCycleButton: (CGFloat)fromL toLevel: (CGFloat)toL isIncreased: (BOOL)isIncreased{
    __block CGFloat fl = fromL;
    [UIView animateWithDuration:0.01 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [self setCycleButtonLocationWithLevel:fromL];
    } completion:^(BOOL finished) {
        if (isIncreased) {
            fl += 0.04;
            if (fl <= toL) {
                [self smoothCycleButton:fl toLevel:toL isIncreased:isIncreased];
            }else if ((fl - 0.04) < toL) {
                [self smoothCycleButton:toL toLevel:toL isIncreased:isIncreased];
            }
        }else{
            fl -= 0.04;
            if (fl >= toL) {
                [self smoothCycleButton:fl toLevel:toL isIncreased:isIncreased];
            }else if ((fl + 0.04) > toL) {
                [self smoothCycleButton:toL toLevel:toL isIncreased:isIncreased];
            }
        }
    }];
}

- (void)setPositionFromOrigin: (CGFloat)origin toCurrent: (CGFloat)current {
    if (origin < current) {
        
//        for (CGFloat i = origin; i <= current; i = i + 0.01) {
//            [self setCycleButtonLocationWithLevel:i];
//        }
        [self smoothCycleButton:origin toLevel:current isIncreased:YES];
    }else{
//        for (CGFloat i = origin; i >= current; i = i - 0.01) {
//            [self setCycleButtonLocationWithLevel:i];
//        }
        [self smoothCycleButton:origin toLevel:current isIncreased:NO];
    }
}

- (CGFloat)getLevelWithPosition: (CGPoint)point {
    CGPoint newPoint;
    
    newPoint.x = point.x - r;
    newPoint.y = r - point.y;
    
    CGFloat dc = sqrt(newPoint.x * newPoint.x + newPoint.y * newPoint.y);
    newPoint.x = newPoint.x * r1 / dc;
    newPoint.y = newPoint.y * r1 / dc;
    
    if (newPoint.x < maxPoint.x && newPoint.x > minPoint.x && newPoint.y < maxPoint.y) {
        return - 1;
    }
    
    CGFloat currentAngle = atan(newPoint.y / newPoint.x);
    
    if (newPoint.x > 0 && newPoint.y <= 0) {
        currentAngle = M_PI + angle - currentAngle;
    }else if (newPoint.x <= 0 && newPoint.y > 0) {
        currentAngle = angle - currentAngle;
    }else if (newPoint.x < 0 && newPoint.y <= 0) {
        currentAngle = angle - currentAngle;
    }else if (newPoint.x > 0 && newPoint.y > 0) {
        currentAngle = M_PI + angle - currentAngle;
    }
    
    CGFloat currentLevel = currentAngle / (M_PI + 2 * angle);
    
    return currentLevel;
}

- (void)initPositionOfControls {
    CGFloat w = self.view.frame.size.width;
    CGFloat h = self.view.frame.size.height;
    
//    self.baseScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
//    [self.baseScrollView setScrollEnabled:YES];
//    [self baseScrollView].delegate = self;
//    [self.baseScrollView setPagingEnabled:YES];
//    [self.baseScrollView setContentSize:CGSizeMake(w, h * 1117.0f / 667.0f)];

    //-- Background ImageView
    
    self.backgroundImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    [self.backgroundImageView setImage:[UIImage imageNamed:@"background.png"]];
    [self.view addSubview:self.backgroundImageView];
//    [self.baseScrollView addSubview:backgroundImageView];
    
//    [self.view addSubview:self.baseScrollView];
    
    //--< Base View >
    self.baseView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h * 1117.0f / 667.0f)];

    [self.baseView setBackgroundColor:[UIColor clearColor]];
    [self.view addSubview:self.baseView];
//    [self.baseScrollView addSubview:self.baseView];
    
    //-------First View
    self.firstView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    [self.firstView setBackgroundColor:[UIColor clearColor]];
    [self.baseView addSubview:self.firstView];
    
    CGFloat cvw = h * 290.0f / 667.0f;// cycleView Width
    CGFloat cvh = cvw; //cycleView Height
    self.cycleView = [[UIView alloc] initWithFrame:CGRectMake((w - cvw) / 2.0f, h * 400.0f / 667.0f - cvh, cvw, cvh)];
    [self.cycleView setBackgroundColor:[UIColor clearColor]];
    [self.firstView addSubview:self.cycleView];
    
    self.cycleImageV = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, cvw, cvh)];
    [self.cycleImageV setImage:[UIImage imageNamed:@"lightcycle.png"]];
    [self.cycleView addSubview:self.cycleImageV];
    
    self.cycleButton = [[UIButton alloc] init];
    [self.cycleButton setBackgroundImage:[UIImage imageNamed:@"lightbutton.png"] forState:UIControlStateNormal];
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panForCycleButton:)];
    [panGesture setMaximumNumberOfTouches:1];
    [panGesture setMinimumNumberOfTouches:1];
    [self.cycleButton addGestureRecognizer:panGesture];
    
    [self initCycleData];
    [self initPositionForCycleButton];
    
    [self.cycleView addSubview:self.cycleButton];
    //----
    self.timeLabel = [[MyLabel alloc] initWithFrame:CGRectMake(self.cycleView.frame.size.width / 6, self.cycleView.frame.size.height / 3, self.cycleView.frame.size.width * 2 / 3, self.cycleView.frame.size.height / 3)];
    self.timeLabel.text = @"";
    self.timeLabel.numberOfLines = 1;
    self.timeLabel.adjustsFontSizeToFitWidth = YES;
    self.timeLabel.textAlignment = NSTextAlignmentCenter;
//    [self.timeLabel setFont:[UIFont systemFontOfSize:self.timeLabel.frame.size.height * 3 / 4 weight:UIFontWeightSemibold]];
    [self.timeLabel setFont:[UIFont fontWithName:@"Arial Rounded MT Bold" size:self.timeLabel.frame.size.height * 3 / 4]];
    [self.timeLabel setTextColor:[UIColor clearColor]];
//    [self.timeLabel setBackgroundColor:[UIColor greenColor]];
//    [self countingTime];
    [self.cycleView addSubview:self.timeLabel];
    //----
    self.ringImageView = [[UIImageView alloc] initWithFrame:CGRectMake(self.cycleView.frame.size.width * 2 / 5, self.cycleView.frame.size.height * 2 / 3, self.cycleView.frame.size.width / 4, self.cycleView.frame.size.height / 4)];
    
    self.ringImageView.animationImages = [NSArray arrayWithObjects:[UIImage imageNamed:@"1.png"]
                                          , [UIImage imageNamed:@"2.png"]
                                          , [UIImage imageNamed:@"3.png"]
                                          , [UIImage imageNamed:@"4.png"]
                                          , [UIImage imageNamed:@"5.png"]
                                          , [UIImage imageNamed:@"6.png"]
                                          , [UIImage imageNamed:@"7.png"]
                                          , [UIImage imageNamed:@"8.png"]
                                          , [UIImage imageNamed:@"9.png"]
                                          , [UIImage imageNamed:@"10.png"]
                                          , nil];
    [self.ringImageView setAnimationDuration:1.5];
    
    [self.ringImageView setImage:[UIImage imageNamed:@"ic_ring.png"]];
    
    UIButton *ringButton = [[UIButton alloc] initWithFrame:CGRectMake(self.cycleView.frame.size.width * 2 / 5, self.cycleView.frame.size.height * 2 / 3, self.cycleView.frame.size.width / 4, self.cycleView.frame.size.height / 4)];
    [ringButton addTarget:self action:@selector(ringButtonTouchUp:) forControlEvents:UIControlEventTouchUpInside];
    [self.cycleView addSubview:self.ringImageView];
    [self.cycleView addSubview:ringButton];

    self.pushImageView = [[UIImageView alloc] initWithFrame:CGRectMake((w - cvw) / 2.0f, h * 400.0f / 667.0f, cvw, cvh / 2.0f)];
    [self.pushImageView setImage:[UIImage imageNamed:@"pushline.png"]];
    
    self.pushImageView.animationImages = [NSArray arrayWithObjects:[UIImage imageNamed:@"A.png"]
                                          , [UIImage imageNamed:@"B.png"]
                                          , [UIImage imageNamed:@"C.png"]
                                          , [UIImage imageNamed:@"D.png"]
                                          , nil];
    [self.pushImageView setAnimationRepeatCount:4];
    [self.pushImageView setAnimationDuration:2.5];
    
    [self.firstView addSubview:self.pushImageView];
    
    CGFloat bw = 50; //updown button width
    self.upDownButton = [[UIButton alloc] initWithFrame:CGRectMake((w - bw) / 2.0f, h - bw, bw, bw)];
    [self.upDownButton addTarget:self action:@selector(pushView:) forControlEvents:UIControlEventTouchUpInside];
    [self.upDownButton setBackgroundImage:[UIImage imageNamed:@"ic_down.png"] forState:UIControlStateNormal];
    [self.firstView addSubview:self.upDownButton];
    
    //-------Second View
    self.secondView = [[UIView alloc] initWithFrame:CGRectMake(0, h, w, h * 450.0f / 667.0f)];
    [self.secondView setBackgroundColor:[UIColor clearColor]];
    [self.baseView addSubview:self.secondView];
    
    CGFloat margin = self.view.frame.size.width / 10;
    CGFloat largeFontSize = self.secondView.frame.size.height / 24;
    CGFloat smallFontSize = self.secondView.frame.size.height / 30;
    CGFloat itemHei = self.secondView.frame.size.height * 2 / 15;

    UILabel *alarmLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, 0, self.view.frame.size.width - margin * 2 - 49, itemHei)];
    alarmLabel.text = @"ALARM";
    alarmLabel.textAlignment = NSTextAlignmentLeft;
    [alarmLabel setFont:[UIFont systemFontOfSize:largeFontSize weight:UIFontWeightSemibold]];
    [alarmLabel setTextColor:[UIColor whiteColor]];
    [self.secondView addSubview:alarmLabel];
    
    self.alarmSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(self.view.frame.size.width - margin - 49, (itemHei - 31) / 2.0f, 0, 0)];
    [self.alarmSwitch setOnTintColor:[UIColor colorWithRed:220.0f / 255.0f green:220.0f / 255.0f blue:220.0f / 255.0f alpha:1]];
    [self.alarmSwitch addTarget:self action:@selector(alarmSwitch:) forControlEvents:UIControlEventValueChanged];
    [self.secondView addSubview:self.alarmSwitch];
///---------------------------------
    timePicker = [[TimePicker alloc] initWithFrame:CGRectMake(margin / 2, itemHei, self.view.frame.size.width - margin, itemHei)];
    timePicker.delegate = self;

    [self.secondView addSubview:timePicker];
///---------------------------------
    UILabel *lightAlarmLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, itemHei * 2, self.view.frame.size.width - margin * 2 - 49, itemHei)];
    lightAlarmLabel.text = @"LIGHT ON ALARM";
    lightAlarmLabel.textAlignment = NSTextAlignmentLeft;
    [lightAlarmLabel setFont:[UIFont systemFontOfSize:largeFontSize weight:UIFontWeightSemibold]];
    [lightAlarmLabel setTextColor:[UIColor whiteColor]];
//    [lightAlarmLabel setBackgroundColor:[UIColor blackColor]];//--
    [self.secondView addSubview:lightAlarmLabel];
    
    self.alarmOnDescriptionLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, self.secondView.frame.size.height / 2 - itemHei, self.secondView.frame.size.width - 2 * margin, itemHei)];
    [self.alarmOnDescriptionLabel setText:@"Pressing Home or Power buttons will disable light when alarm triggers"];
    [self.alarmOnDescriptionLabel setTextAlignment:NSTextAlignmentLeft];
    [self.alarmOnDescriptionLabel setNumberOfLines:2];
    [self.alarmOnDescriptionLabel setFont:[UIFont systemFontOfSize:smallFontSize]];
    [self.alarmOnDescriptionLabel setTextColor:[UIColor whiteColor]];
    [self.secondView addSubview:self.alarmOnDescriptionLabel];
    
    self.lightAlarmSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(self.view.frame.size.width - margin - 49, itemHei * 2 + (itemHei - 31) / 2.0f, 0, 0)];
    [self.lightAlarmSwitch addTarget:self action:@selector(lightAlarmSwitch:) forControlEvents:UIControlEventValueChanged];
    [self.lightAlarmSwitch setOnTintColor:[UIColor colorWithRed:220.0f / 255.0f green:220.0f / 255.0f blue:220.0f / 255.0f alpha:1]];
    [self.secondView addSubview:self.lightAlarmSwitch];
///---------------------------------
    UILabel *desLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, self.secondView.frame.size.height / 2, self.view.frame.size.width - margin * 2, itemHei)];
    desLabel.text = @"LIGHT CONTROL GESTURES";
    desLabel.textAlignment = NSTextAlignmentLeft;
    [desLabel setFont:[UIFont systemFontOfSize:largeFontSize weight:UIFontWeightSemibold]];
    [desLabel setTextColor:[UIColor whiteColor]];
//    [desLabel setBackgroundColor:[UIColor blackColor]];//-
    [self.secondView addSubview:desLabel];
///---------------------------------
    UILabel *waveLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, self.secondView.frame.size.height / 2 + itemHei, self.secondView.frame.size.width / 2 - margin - 49, itemHei)];
    waveLabel.text = @"WAVE";
    waveLabel.textAlignment = NSTextAlignmentLeft;
    [waveLabel setFont:[UIFont systemFontOfSize:largeFontSize weight:UIFontWeightSemibold]];
    [waveLabel setTextColor:[UIColor whiteColor]];
    [self.secondView addSubview:waveLabel];
    
    self.waveSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(self.view.frame.size.width / 2 - 69, self.secondView.frame.size.height / 2 + itemHei + (itemHei - 31) / 2.0f, 0, 0)];
    [self.waveSwitch setOnTintColor:[UIColor colorWithRed:220.0f / 255.0f green:220.0f / 255.0f blue:220.0f / 255.0f alpha:1]];
    [self.waveSwitch addTarget:self action:@selector(waveSwitch:) forControlEvents:UIControlEventValueChanged];
    [self.secondView addSubview:self.waveSwitch];

    UILabel *clapLabel = [[UILabel alloc] initWithFrame:CGRectMake(self.view.frame.size.width / 2 + 20, self.secondView.frame.size.height / 2 + itemHei, self.secondView.frame.size.width / 2 - margin - 69, itemHei)];
    clapLabel.text = @"CLAP";
    clapLabel.textAlignment = NSTextAlignmentLeft;
    [clapLabel setFont:[UIFont systemFontOfSize:largeFontSize weight:UIFontWeightSemibold]];
    [clapLabel setTextColor:[UIColor whiteColor]];
    [self.secondView addSubview:clapLabel];
    
    self.clapSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(self.view.frame.size.width - margin - 49, self.secondView.frame.size.height / 2 + itemHei + (itemHei - 31) / 2.0f, 0, 0)];
    [self.clapSwitch setOnTintColor:[UIColor colorWithRed:220.0f / 255.0f green:220.0f / 255.0f blue:220.0f / 255.0f alpha:1]];
    [self.clapSwitch addTarget:self action:@selector(clapSwitch:) forControlEvents:UIControlEventValueChanged];
    [self.secondView addSubview:self.clapSwitch];
///----------------------------------
    UILabel *expLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, self.secondView.frame.size.height / 2 + itemHei * 2, self.secondView.frame.size.width - margin * 2, itemHei)];
    expLabel.text = @"Wave your hands to dim the light. Clap twice to turn on and off.";
    [expLabel setNumberOfLines:0];
    expLabel.textAlignment = NSTextAlignmentLeft;
    [expLabel setFont:[UIFont systemFontOfSize:smallFontSize weight:UIFontWeightSemibold]];
    [expLabel setTextColor:[UIColor whiteColor]];
    [self.secondView addSubview:expLabel];
}

- (void)showAlarmOnDescription {
    [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [self.alarmOnDescriptionLabel setAlpha:1];
    } completion:^(BOOL finished) {
        
    }];
}

- (void)hideAlarmOnDescription {
    [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [self.alarmOnDescriptionLabel setAlpha:0];
    } completion:^(BOOL finished) {
        
    }];
}

@end
