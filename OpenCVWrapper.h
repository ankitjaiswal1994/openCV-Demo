//
//  OpenCVWrapper.h
//  OpenCv Demo
//
//  Created by Ankit Jaiswal on 23/11/18.
//  Copyright © 2018 Ankit Jaiswal. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVWrapper : NSObject

+ (NSString *)openCVVersionString;
- (void)cvMatFromUIImage:(UIImage *)image;
@property (assign) UIImageView *originalImage;
@property (assign) UIImageOrientation orientation;

@end

NS_ASSUME_NONNULL_END
