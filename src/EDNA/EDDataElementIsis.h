//
//  EDDataElementIsis.h
//  BARTApplication
//
//  Created by Lydia Hellrung on 5/4/10.
//  Copyright 2010 MPI Cognitive and Human Brain Sciences Leipzig. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "../BARTMainApp/BADataElement.h"
#import "DataStorage/image.hpp"


@interface EDDataElementIsis : BADataElement {
	//isis::data::ImageList mIsisImageList;
	std::list<isis::data::Image> mIsisImageList; 
    isis::data::Image *mIsisImage;
	//isis::data::ChunkList mChunkList;
	std::list<isis::data::Chunk> mChunkList;
	
	
}

-(void)appendVolume:(BADataElement*)nextVolume;
-(BOOL)sizeCheckRows:(uint)r Cols:(uint)c Slices:(uint)s Timesteps:(uint)t;
-(id)initFromImage:(isis::data::Image)img ofImageType:(enum ImageType)imgType;


@end
