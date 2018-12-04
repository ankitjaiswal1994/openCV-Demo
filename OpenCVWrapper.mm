//
//  OpenCVWrapper.m
//  OpenCv Demo
//
//  Created by Ankit Jaiswal on 23/11/18.
//  Copyright © 2018 Ankit Jaiswal. All rights reserved.
//

#import "OpenCVWrapper.h"
#import <opencv2/opencv.hpp>
#import <UIKit/UIKit.h>

@implementation OpenCVWrapper

@synthesize originalImage, orientation;

cv::Mat originalCV;

struct ImageDetails {
    cv::Mat speed;
    double width;
    double height;
};

+ (NSString *)openCVVersionString {
    return [NSString stringWithFormat:@"OpenCV Version %s",  CV_VERSION];
}

double angle( cv::Point pt1, cv::Point pt2, cv::Point pt0 ) {
    double dx1 = pt1.x - pt0.x;
    double dy1 = pt1.y - pt0.y;
    double dx2 = pt2.x - pt0.x;
    double dy2 = pt2.y - pt0.y;
    return (dx1*dx2 + dy1*dy2)/sqrt((dx1*dx1 + dy1*dy1)*(dx2*dx2 + dy2*dy2) + 1e-10);
}

- (void)cvMatFromUIImage:(UIImage *)image {
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    size_t numberOfComponents = CGColorSpaceGetNumberOfComponents(colorSpace);
    CGFloat cols,rows;
    if (image.imageOrientation == UIImageOrientationLeft
        || image.imageOrientation == UIImageOrientationRight) {
        cols = image.size.height;
        rows = image.size.width;
    } else {
        cols = image.size.width;
        rows = image.size.height;
    }
    
    orientation = image.imageOrientation;
    cv::Mat cvMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels
    CGBitmapInfo bitmapInfo = kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault;
    
    // check whether the UIImage is greyscale already
    if (numberOfComponents == 1){
        cvMat = cv::Mat(rows, cols, CV_8UC1); // 8 bits per component, 1 channels
        bitmapInfo = kCGImageAlphaNone | kCGBitmapByteOrderDefault;
    }
    
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,             // Pointer to backing data
                                                    cols,                       // Width of bitmap
                                                    rows,                       // Height of bitmap
                                                    8,                          // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    bitmapInfo);              // Bitmap info flags
    
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
    
    originalCV = cvMat;
    [self findSquaresInImage:cvMat];
}

- (std::vector<std::vector<cv::Point> >)findSquaresInImage:(cv::Mat)_image {
    std::vector<std::vector<cv::Point> > squares;
    cv::Mat pyr, timg, gray0(_image.size(), CV_8U), gray;
    int thresh = 50, N = 11;
    cv::pyrDown(_image, pyr, cv::Size(_image.cols/2, _image.rows/2));
    cv::pyrUp(pyr, timg, _image.size());
    std::vector<std::vector<cv::Point> > contours;
    for( int c = 0; c < 3; c++ ) {
        int ch[] = {c, 0};
        mixChannels(&timg, 1, &gray0, 1, ch, 1);
        for( int l = 0; l < N; l++ ) {
            if( l == 0 ) {
                // Use Canny instead of zero threshold level!
                // Canny helps to catch squares with gradient shading
                
                cv::Canny(gray0, gray, 20*7*7, 40*7*7, 7);
                
                // Dilate helps to remove potential holes between edge segments
                cv::dilate(gray, gray, cv::Mat(), cv::Point(-1,-1));
            }
            else {
                gray = gray0 >= (l+1)*255/N;
            }
            cv::findContours(gray, contours, cv::RETR_LIST, cv::CHAIN_APPROX_SIMPLE);
            std::vector<cv::Point> approx;
            for( size_t i = 0; i < contours.size(); i++ ) {
                    cv::approxPolyDP(cv::Mat(contours[i]), approx, arcLength(cv::Mat(contours[i]), true)*0.02, true);
                    if (approx.size() == 4 && fabs(contourArea(cv::Mat(approx))) > 1000 && cv::isContourConvex(cv::Mat(approx))) {

                        double maxCosine = 0;
                        
                        for( int j = 2; j < 5; j++ )
                        {
                            double cosine = fabs(angle(approx[j%4], approx[j-2], approx[j-1]));
                            maxCosine = MAX(maxCosine, cosine);
                        }
                        
                        if( maxCosine < 0.3 ) {
                            squares.push_back(approx);
                        }
                }
            }
        }
    }

    //UIImage *editedImage = [self UIImageFromCVMat:];
    [self debugSquares:squares,_image];

    return squares;
}

- (void) debugSquares:(std::vector<std::vector<cv::Point>>) squares, cv::Mat image {
    NSMutableArray *colors = [NSMutableArray array];
    NSMutableArray *myIntegers = [NSMutableArray array];
    __block CGFloat oldr=0, oldg=0, oldb=0, diff=0;
    __block std::vector<cv::Point> a4Sheet;
    __block UIImage *object;
    __block UIColor *color;
    __block bool isDetected = false;
    NSOperation *finalOperation = [NSBlockOperation blockOperationWithBlock:^{
            for (int i=0; i< colors.count; i++) {
                //Using logic to find image which is more white in color
                CGFloat r =0, g=0, b=0, a=0;
                [colors[i] getRed:&r green:&g blue:&b alpha:&a];
                CGFloat average = (ABS(r-1) + ABS(g-1) + ABS(b-1))/3;
                
                if (i == 0) {
                    diff = average;
                }
                
                if (average <= diff) {
                    
                    isDetected = true;
                    diff = average;
                    oldr = r;
                    oldg = g;
                    oldb = b;
                    int o = [[myIntegers objectAtIndex:i] integerValue];
                    a4Sheet = squares[o];
                }
            }
        if (isDetected) {
            cv::Rect rect = boundingRect(cv::Mat(a4Sheet));
            cv::rectangle(originalCV, rect.tl(), rect.br(), cv::Scalar(0,255,0), 5, 8, 0);
            dispatch_async(dispatch_get_main_queue(), ^{
                self->originalImage.image = [self UIImageFromCVMat:image];
            });
        }
    }];
    NSOperationQueue *operationqueue = [[NSOperationQueue alloc] init];
    operationqueue.qualityOfService = NSQualityOfServiceUserInteractive;
    
    for ( int i = 0; i< squares.size(); i++ ) {
        NSOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
            // draw bounding rect
            ImageDetails paperImage = [self getPaperAreaFromImage:squares[i], image];
            object = [self UIImageFromCVMat:paperImage.speed];
            [colors addObject:[self averageColor:object]];
            [myIntegers addObject:[NSNumber numberWithInteger:i]];
        }];

        //final operation is dependent on all others
        [finalOperation addDependency:operation];
        [operationqueue addOperation:operation];
    }
    
    [operationqueue addOperation:finalOperation];
}

- (UIImage *)UIImageFromCVMat:(cv::Mat)cvMat {
    cv::cvtColor(cvMat, cvMat, cv::COLOR_BGR2RGB);

    NSData *data = [NSData dataWithBytes:cvMat.data length:cvMat.step.p[0]*cvMat.rows];
    
    CGColorSpaceRef colorSpace;
    CGBitmapInfo bitmapInfo;
    
    if (cvMat.elemSize() == 1) {
        colorSpace = CGColorSpaceCreateDeviceGray();
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
       /* bitmapInfo = kCGBitmapByteOrder32Little | (
                                                   cvMat.elemSize() == 3 ? kCGImageAlphaNone : kCGImageAlphaNoneSkipFirst
                                                   ); */
    }
    bitmapInfo = kCGImageAlphaNone | kCGBitmapByteOrderDefault;
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    // Creating CGImage from cv::Mat
    CGImageRef imageRef = CGImageCreate(
                                        cvMat.cols,                 //width
                                        cvMat.rows,                 //height
                                        8,                          //bits per component
                                        8 * cvMat.elemSize(),       //bits per pixel
                                        cvMat.step[0],              //bytesPerRow
                                        colorSpace,                 //colorspace
                                        bitmapInfo,                 // bitmap info
                                        provider,                   //CGDataProviderRef
                                        NULL,                       //decode
                                        false,                      //should interpolate
                                        kCGRenderingIntentDefault   //intent
                                        );

    // Getting UIImage from CGImage
    UIImage *finalImage = [[UIImage alloc] initWithCGImage:imageRef scale:1 orientation: orientation];
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    return finalImage;
}

- (cv::Mat) cvMatWithImage:(UIImage *)image
{
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    size_t numberOfComponents = CGColorSpaceGetNumberOfComponents(colorSpace);
    
    CGFloat cols,rows;
    if (image.imageOrientation == UIImageOrientationLeft
        || image.imageOrientation == UIImageOrientationRight) {
        cols = image.size.height;
        rows = image.size.width;
    } else {
        cols = image.size.width;
        rows = image.size.height;
    }

    cv::Mat cvMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels
    CGBitmapInfo bitmapInfo = kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault;
    
    // check whether the UIImage is greyscale already
    if (numberOfComponents == 1){
        cvMat = cv::Mat(rows, cols, CV_8UC1); // 8 bits per component, 1 channels
        bitmapInfo = kCGImageAlphaNone | kCGBitmapByteOrderDefault;
    }
    
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,             // Pointer to backing data
                                                    cols,                       // Width of bitmap
                                                    rows,                       // Height of bitmap
                                                    8,                          // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    bitmapInfo);              // Bitmap info flags
    
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
    
    return cvMat;
}

cv::Point getCenter( std::vector<cv::Point> points ) {
    
    cv::Point center = cv::Point( 0.0, 0.0 );
    
    for( size_t i = 0; i < points.size(); i++ ) {
        center.x += points[ i ].x;
        center.y += points[ i ].y;
    }
    
    center.x = center.x / points.size();
    center.y = center.y / points.size();
    
    return center;
}

// Helper;
// 0----1
// |    |
// |    |
// 3----2
std::vector<cv::Point> sortSquarePointsClockwise( std::vector<cv::Point> square ) {
    
    cv::Point center = getCenter( square );
    
    std::vector<cv::Point> sorted_square;
    for( size_t i = 0; i < square.size(); i++ ) {
        if ( (square[i].x - center.x) < 0 && (square[i].y - center.y) < 0 ) {
            switch( i ) {
                case 0:
                    sorted_square = square;
                    break;
                case 1:
                    sorted_square.push_back( square[1] );
                    sorted_square.push_back( square[2] );
                    sorted_square.push_back( square[3] );
                    sorted_square.push_back( square[0] );
                    break;
                case 2:
                    sorted_square.push_back( square[2] );
                    sorted_square.push_back( square[3] );
                    sorted_square.push_back( square[0] );
                    sorted_square.push_back( square[1] );
                    break;
                case 3:
                    sorted_square.push_back( square[3] );
                    sorted_square.push_back( square[0] );
                    sorted_square.push_back( square[1] );
                    sorted_square.push_back( square[2] );
                    break;
            }
            break;
        }
    }
    
    return sorted_square;
    
}

// Helper
float distanceBetweenPoints( cv::Point p1, cv::Point p2 ) {
    
    if( p1.x == p2.x ) {
        return abs( p2.y - p1.y );
    }
    else if( p1.y == p2.y ) {
        return abs( p2.x - p1.x );
    }
    else {
        float dx = p2.x - p1.x;
        float dy = p2.y - p1.y;
        return sqrt( (dx*dx)+(dy*dy) );
    }
}

- (ImageDetails) getPaperAreaFromImage: (std::vector<cv::Point>) square, cv::Mat image {
    ImageDetails details;
    // declare used vars
    int paperWidth  = 210; // in mm, because scale factor is taken into account
    int paperHeight = 297; // in mm, because scale factor is taken into account
    cv::Point2f imageVertices[4];
    float distanceP1P2;
    float distanceP1P3;
    BOOL isLandscape = true;
    int scaleFactor;
    cv::Mat paperImage;
    cv::Mat paperImageCorrected;
    cv::Point2f paperVertices[4];
    
    // sort square corners for further operations
    //square = sortSquarePointsClockwise( square );
    
    // rearrange to get proper order for getPerspectiveTransform()
    imageVertices[0] = square[0];
    imageVertices[1] = square[1];
    imageVertices[2] = square[3];
    imageVertices[3] = square[2];
    
    // get distance between corner points for further operations
    distanceP1P2 = distanceBetweenPoints( imageVertices[0], imageVertices[1] );
    distanceP1P3 = distanceBetweenPoints( imageVertices[0], imageVertices[2] );
    
    // calc paper, paperVertices; take orientation into account
    if ( distanceP1P2 > distanceP1P3 ) {
        scaleFactor =  ceil( lroundf(distanceP1P2/paperHeight) ); // we always want to scale the image down to maintain the best quality possible
        paperImage = cv::Mat( paperWidth*scaleFactor, paperHeight*scaleFactor, CV_8UC3 );
        paperVertices[0] = cv::Point( 0, 0 );
        paperVertices[1] = cv::Point( paperHeight*scaleFactor, 0 );
        paperVertices[2] = cv::Point( 0, paperWidth*scaleFactor );
        paperVertices[3] = cv::Point( paperHeight*scaleFactor, paperWidth*scaleFactor );
    }
    else {
        isLandscape = false;
        scaleFactor =  ceil( lroundf(distanceP1P3/paperHeight) ); // we always want to scale the image down to maintain the best quality possible
        paperImage = cv::Mat( paperHeight*scaleFactor, paperWidth*scaleFactor, CV_8UC3 );
        paperVertices[0] = cv::Point( 0, 0 );
        paperVertices[1] = cv::Point( paperWidth*scaleFactor, 0 );
        paperVertices[2] = cv::Point( 0, paperHeight*scaleFactor );
        paperVertices[3] = cv::Point( paperWidth*scaleFactor, paperHeight*scaleFactor );
    }
    
    cv::Mat warpMatrix = getPerspectiveTransform( imageVertices, paperVertices );
    cv::warpPerspective(image, paperImage, warpMatrix, paperImage.size(), cv::INTER_LINEAR, cv::BORDER_CONSTANT );
    
    // we want portrait output
    if ( isLandscape ) {
        cv::transpose(paperImage, paperImageCorrected);
        cv::flip(paperImageCorrected, paperImageCorrected, 1);
        details.speed = paperImageCorrected;
        details.width = paperVertices[3].x;
        details.height = paperVertices[3].y;
        return details;
    }
    
    details.speed = paperImage;
    details.width = paperVertices[3].x;
    details.height = paperVertices[3].y;

    return details;
}

- (UIColor *)averageColor: (UIImage *) image {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    unsigned char rgba[4];
    CGContextRef context = CGBitmapContextCreate(rgba, 1, 1, 8, 4, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), image.CGImage);
    CGColorSpaceRelease(colorSpace);
    CGContextRelease(context);
    
    if(rgba[3] > 0) {
        CGFloat alpha = ((CGFloat)rgba[3])/255.0;
        CGFloat multiplier = alpha/255.0;
        return [UIColor colorWithRed:((CGFloat)rgba[0])*multiplier
                               green:((CGFloat)rgba[1])*multiplier
                                blue:((CGFloat)rgba[2])*multiplier
                               alpha:alpha];
    }
    else {
        return [UIColor colorWithRed:((CGFloat)rgba[0])/255.0
                               green:((CGFloat)rgba[1])/255.0
                                blue:((CGFloat)rgba[2])/255.0
                               alpha:((CGFloat)rgba[3])/255.0];
    }
}

@end
