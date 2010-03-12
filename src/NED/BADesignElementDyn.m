//
//  BADesignElementDyn.m
//  BARTApplication
//
//  Created by FirstLast on 1/29/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "BADesignElementDyn.h"

#import <fftw3.h>

#include <viaio/VImage.h>

#import "COSystemConfig.h"

extern int VStringToken (char *, char *, int, int);

// komische Konstanten erstmal aus vgendesign.c (Lipsia) uebernommen
static const int BUFFER_LENGTH = 10000;
//static const int MAX_NUMBER_TRIALS = 5000;
static const int MAX_NUMBER_EVENTS = 100;

//static const unsigned int MAX_NUMBER_TIMESTEPS = 1000;
const TrialList TRIALLIST_INIT = { {0,0,0,0}, NULL};

@interface BADesignElementDyn (PrivateMethods)

/* Standard parameter values for gamma function, Glover 99. */
double a1 = 6.0;     
double b1 = 0.9;
double a2 = 12.0;
double b2 = 0.9;
double cc = 0.35;

/* Generated design information/resulting design image. */
float** mDesign = NULL;
float** mCovariates = NULL;
//int numberRegressors = 0;
//int numberCovariates = 0;     // TODO: get from config  
//
///* Attributes that should be modifiable (were once CLI parameters). */
//short bkernel = 0;
//short deriv = 0;
//float block_threshold = 10.0; // in seconds
//int ntimesteps = 396;         // Must be set to a different value!

//float tr = 2.0;               // Must be set to a different value!
int mNumberRegressors = 0;
int mNumberCovariates = 0;     // TODO: get from config  

/* Attributes that should be modifiable (were once CLI parameters). */
short mKernelForBlockDesign = 0;
int mDerivationsHrf = 0;
float mBlockThreshold = 10.0; // in seconds



/* Other Attributes set up by initDesign. Main use in generate Design. */
int numberSamples;
unsigned int initNumberSamples;
double samplingRateInMs = 20.0;           /* Temporal resolution for convolution is 20 ms. */
double t1 = 30.0;              /* HRF duration / Breite der HRF.                */

fftw_complex *fkernelg = NULL;
fftw_complex *fkernel0 = NULL;
fftw_complex *fkernel1 = NULL;
fftw_complex *fkernel2 = NULL;

double **forwardInBuffers = NULL;
fftw_plan *forwardFFTplans;
fftw_plan *inverseFFTplans;
double *xx = NULL;
double **inverseOutBuffers = NULL;
fftw_complex **forwardOutBuffers = NULL; // Resulting HRFs (one per Event).
fftw_complex **inverseInBuffers = NULL;
/* Other Attributes END. */

-(NSError*)parseInputFile:(NSString*)path;
-(NSError*)initDesign;

-(Complex)complex_mult:(Complex)a :(Complex)b;
-(double)xgamma:(double)xx :(double)t0;
-(double)bgamma:(double)xx :(double)t0;
-(double)deriv1_gamma:(double)x :(double)t0;
-(double)deriv2_gamma:(double)x :(double)t0;
-(double)xgauss:(double)xx :(double)t0;
-(float**)Plot_gamma;
-(BOOL)test_ascii:(int)val;
-(void)Convolve:(int)col
               :(fftw_complex *)local_nbuf
               :(fftw_complex *)forwardOutBuffer
               :(double *)inverseOutBuffer
               :(fftw_plan)planInverseFFT
               :(fftw_complex *)fkernel;
/* Utility function for TrialList. */
-(void)tl_append:(TrialList*)head
                :(TrialList*)newLast;

-(NSError*)getPropertiesFromConfig;

COSystemConfig *config;

@end

@implementation BADesignElementDyn

// TODO: check if imageDataType still needed (here: float)
-(id)initWithFile:(NSString*)path ofImageDataType:(enum ImageDataType)type
{
    self = [super init];
    
    if (type == IMAGE_DATA_FLOAT) {
        imageDataType = type;
    } else {
        NSLog(@" BADesignElementDyn.initWithFile: defaulting to IMAGE_DATA_FLOAT (other values are not supported)!");
        imageDataType = IMAGE_DATA_FLOAT;
    }
	
    trials = (TrialList**) malloc(sizeof(TrialList*) * MAX_NUMBER_EVENTS);
    for (int i = 0; i < MAX_NUMBER_EVENTS; i++) {
        trials[i] = NULL;
    }
	
	if (nil == [self getPropertiesFromConfig]){
		return nil;
	}
	
    NSLog(@"GenDesign GCD: START");
	[self parseInputFile:path];
	NSLog(@"GenDesign GCD: PARSE");
    [self initDesign];
	NSLog(@"GenDesign GCD: INIT");   
    [self generateDesign];
    NSLog(@"GenDesign GCD: END");
    
    if (mNumberCovariates > 0) {
        mCovariates = (float**) malloc(sizeof(float*) * mNumberCovariates);
        for (int cov = 0; cov < mNumberCovariates; cov++) {
            mCovariates[cov] = (float*) malloc(sizeof(float) * numberTimesteps);
            memset(mCovariates[cov], 0.0, sizeof(float) * numberTimesteps);
        }
    }
     
    mNumberRegressors = numberEvents * (mDerivationsHrf + 1) + 1;
    numberExplanatoryVariables = mNumberRegressors + mNumberCovariates;

	return self;
}

-(id)initWithDynamicDataOfImageDataType:(enum ImageDataType)type
{
    self = [super init];
    
    if (type == IMAGE_DATA_FLOAT) {
        imageDataType = type;
    } else {
        NSLog(@" BADesignElementDyn.initWithFile: defaulting to IMAGE_DATA_FLOAT (other values are not supported)!");
        imageDataType = IMAGE_DATA_FLOAT;
    }
    
    trials = (TrialList**) malloc(sizeof(TrialList*) * MAX_NUMBER_EVENTS);
    for (int i = 0; i < MAX_NUMBER_EVENTS; i++) {
        trials[i] = NULL;
    }
	numberEvents = 4;//TODO get from config
	numberTimesteps = 396; //TODO get from config
    
    NSLog(@"GenDesign GCD: START");
    [self initDesign];
    [self generateDesign];
    NSLog(@"GenDesign GCD: END");
    
    if (mNumberCovariates > 0) {
        mCovariates = (float**) malloc(sizeof(float*) * mNumberCovariates);
        for (int cov = 0; cov < mNumberCovariates; cov++) {
            mCovariates[cov] = (float*) malloc(sizeof(float) * numberTimesteps);
            memset(mCovariates[cov], 0.0, sizeof(float) * numberTimesteps);
        }
    }
	
	
    mNumberRegressors = numberEvents * (mDerivationsHrf + 1) + 1;
    numberExplanatoryVariables = mNumberRegressors + mNumberCovariates;
    
	
    //[self writeDesignFile:@"/tmp/testDesign.v"];
    
    return self;
}



-(NSError*)getPropertiesFromConfig
{
	config = [COSystemConfig getInstance];
	
	//TODO:  Will be initialized somewhere else
	NSError *err = [config initializeWithContentsOfEDLFile:@"../../tests/CLETUSTests/Init_Links_1.edl"];
	NSLog(@"%@", err);
	if ( nil != err){
		NSLog(@"Where the hell is the edl file");
		return err;
	}
	
	NSString* config_tr = [config getProp:@"/rtExperiment/experimentData/imageModalities/TR"];
	NSNumberFormatter * f = [[NSNumberFormatter alloc] init];
	[f setNumberStyle:NSNumberFormatterDecimalStyle];
	//TODO : Abfrage Einheit der repetition Time
	mRepetitionTimeInMs = [[f numberFromString:config_tr] intValue];
	
	
	
	[f release];//temp for conversion purposes
	
	
	initNumberSamples = (numberTimesteps * mRepetitionTimeInMs) / samplingRateInMs;
	
	mNumberRegressors = 0;
	mNumberCovariates = 0;     // TODO: get from config  
	
	/* Attributes that should be modifiable (were once CLI parameters). */
	mKernelForBlockDesign = 0;
	mDerivationsHrf = 0;
	mBlockThreshold = 10.0; // in seconds
	
	return nil;
	


}

-(NSError*)initDesign
{
    // TODO: parameterize or/and use config
    static char* filename = ""; // for file with scan times (scanfile)    
    static float delay = 6.0;              
    static float understrength = 0.35;
    static float undershoot = 12.0;
    
    static bool zeromean = YES;
    int i;
    int j;
    char buf[BUFFER_LENGTH];

    double total_duration = 0.0;
    double u;

    //VParseFilterCmd(VNumber(options),options,argc,argv,&in_file,&out_file);
    
    /* check command line parameters */
    //    if (understrength < 0)      VError(" understrength must be >= 0");
    //    if (delay < 0)              VError(" delay must be >= 0");
    //    if (deriv < 0 || deriv > 2) VError(" parameter 'deriv' must be < 3");
    
    /* constant TR */
    if (strlen(filename) < 3) {
        
        fprintf(stderr, " TR in ms = %d\n", mRepetitionTimeInMs);
        
        xx = (double *) malloc(sizeof(double) * numberTimesteps);
        for (i = 0; i < numberTimesteps; i++) {
            xx[i] = (double) (i) * mRepetitionTimeInMs;//TODO: Gabi fragen letzter Zeitschritt im moment nicht einbezogen xx[i] = (double) i * tr * 1000.0;
        }
    }
    /* read scan times from file, non-constant TR */
    else {
        FILE *fp = NULL;
        fp = fopen(filename, "r");
        if (!fp) {
            NSString* errorString = [NSString stringWithFormat:@"Could not open file %s!", filename];
            return [NSError errorWithDomain:errorString code:FILEOPEN userInfo:nil];
        }
        
        NSLog(@"Reading scan file: %s\n", filename);
        
        i = 0;
        while (!feof(fp)) {
            for (j = 0; j < BUFFER_LENGTH; j++) buf[j] = '\0';
            fgets(buf, BUFFER_LENGTH, fp);
            if (buf[0] == '%' || buf[0] == '#') continue;
            if (strlen(buf) < 2) continue;
            
            if (![self test_ascii:((int) buf[0])]) {
                return [NSError errorWithDomain:@"Scan file must be a text file!" code:TXT_SCANFILE userInfo:nil];
            }
            i++;
        }
        
        rewind(fp);
        numberTimesteps = i;
        xx = (double *) malloc(sizeof(double) * numberTimesteps);
        i = 0;
        while (!feof(fp)) {
            for (j = 0; j < BUFFER_LENGTH; j++) buf[j] = '\0';
            fgets(buf, BUFFER_LENGTH, fp);
            if (buf[0] == '%' || buf[0] == '#') continue;
            if (strlen(buf) < 2) continue;

            if (sscanf(buf, "%lf", &u) != 1) {
                NSString* errorString = [NSString stringWithFormat:@"Illegal input format, line %d!", i + 1];
                return [NSError errorWithDomain:errorString code:ILLEGAL_INPUT_FORMAT userInfo:nil];
            }
            xx[i] = u * 1000.0;
            i++;
        }
        fclose(fp);
    }
    total_duration = (xx[0] + xx[numberTimesteps - 1]) / 1000.0;
	NSLog(@"x[0]: %lf und xx[last] %lf", xx[0], xx[numberTimesteps - 1]);
    
    NSLog(@"Number timesteps: %d,  experiment duration: %.2f min\n", numberTimesteps, total_duration / 60.0);
    
    total_duration += 10.0; /* add 10 seconds to avoid FFT problems (wrap around) */
    
    /* set gamma function parameters */
    a1 = delay;
    a2 = undershoot;
    cc = understrength;
    
    /*
     ** check amplitude: must have zero mean for parametric designs
     */
    if (zeromean) {
        
        float sum1;
        float sum2;
        float nx;
        float mean;
        float sigma;
        
        for (i = 0; i < numberEvents; i++) {
            sum1 = 0.0;
            sum2 = 0.0;
            nx   = 0.0;
            
            TrialList* currentTrial;
            currentTrial = trials[i];
            
            while (currentTrial != NULL) {
                sum1 += currentTrial->trial.height;
                sum2 += currentTrial->trial.height * currentTrial->trial.height;
                nx++;
                currentTrial = currentTrial->next;
            }
            
            if (nx >= 1) {
                mean  = sum1 / nx;
                if (nx < 1.5) continue;      /* sigma not computable       */
                sigma =  sqrt((double)((sum2 - nx * mean * mean) / (nx - 1.0)));
                if (sigma < 0.01) continue;  /* not a parametric covariate */
                
                /* correct for zero mean */
                currentTrial = trials[i];
                
                while (currentTrial != NULL) {
                    currentTrial->trial.height -= mean;
                    currentTrial = currentTrial->next;
                }
            }
        }
    }
    if (numberEvents < 1) {
        return [NSError errorWithDomain:@"No events were found!" code:NO_EVENTS_FOUND userInfo:nil];
    }
    
    float xmin;
    int ncols = 0;
    for (i = 0; i < numberEvents; i++) {
        
        xmin = FLT_MAX;
        
        TrialList* currentTrial;
        currentTrial = trials[i];
        
        while (currentTrial != NULL) {
            if (currentTrial->trial.duration < xmin) {
                xmin = currentTrial->trial.duration;
            }
            currentTrial = currentTrial->next;
        }
        
        if (0 == mDerivationsHrf) {
            ncols++;
        } else if (1 == mDerivationsHrf) {
            ncols += 2;
        } else if (2 == mDerivationsHrf) {
            ncols += 3;
        }
    }
    
    NSLog(@"# number of events: %d,  num columns in design matrix: %d\n", numberEvents, ncols + 1);
    
    mDesign = (float**) malloc(sizeof(float*) * (ncols + 1));
    for (int col = 0; col < ncols + 1; col++) {
        mDesign[col] = (float*) malloc(sizeof(float) * numberTimesteps);
         for (int ts = 0; ts < numberTimesteps; ts++) {
             if (col == ncols) {
                 mDesign[col][ts] = 1.0;
             } else {
                 mDesign[col][ts] = 0.0;
             }
         }
    }
    
	
    /* alloc memory */
    numberSamples = (int) (total_duration * 1000.0 / samplingRateInMs);
	NSLog(@"numberSamples %d", numberSamples);
	NSLog(@"total duration %lf", total_duration);
    
    //    if (n > 300000) { /* reduce to 30 ms, if too big */
    //        samplingRateInMs = 30.0;
    //        n = (int) (total_duration * 1000.0 / samplingRateInMs);
    //    }
    
    int nc = (initNumberSamples / 2) + 1;//numberSamples

    /* make plans */
    forwardFFTplans = (fftw_plan *) malloc(sizeof(fftw_plan) * numberEvents);
    inverseFFTplans = (fftw_plan *) malloc(sizeof(fftw_plan) * numberEvents);
    
    forwardInBuffers = (double **) malloc(sizeof(double *) * numberEvents);
    forwardOutBuffers = (fftw_complex **) malloc(sizeof(fftw_complex *) * numberEvents);
    inverseInBuffers = (fftw_complex **) malloc(sizeof(fftw_complex *) * numberEvents);
    inverseOutBuffers = (double **) malloc(sizeof(double *) * numberEvents);
    
    for (int eventNr = 0; eventNr < numberEvents; eventNr++) {
        
        forwardInBuffers[eventNr] = (double *) fftw_malloc(sizeof(double) * initNumberSamples);
        forwardOutBuffers[eventNr] = (fftw_complex *) fftw_malloc(sizeof(fftw_complex) * nc);
        memset(forwardInBuffers[eventNr], 0, sizeof(double) * initNumberSamples);
        
        inverseInBuffers[eventNr] = (fftw_complex *) fftw_malloc(sizeof(fftw_complex) * nc);
        inverseOutBuffers[eventNr] = (double *) fftw_malloc(sizeof(double) * initNumberSamples);
        memset(inverseOutBuffers[eventNr], 0, sizeof(double) * initNumberSamples);

        forwardFFTplans[eventNr] = fftw_plan_dft_r2c_1d(initNumberSamples, forwardInBuffers[eventNr], forwardOutBuffers[eventNr], FFTW_ESTIMATE);
        inverseFFTplans[eventNr] = fftw_plan_dft_c2r_1d(initNumberSamples, inverseInBuffers[eventNr], inverseOutBuffers[eventNr], FFTW_ESTIMATE);
		
    }
    
    /* get kernel */
    double *block_kernel = NULL;
    block_kernel = (double *) fftw_malloc(sizeof(double) * initNumberSamples);
    fkernelg = (fftw_complex *) fftw_malloc (sizeof(fftw_complex) * nc);
    memset(block_kernel, 0, sizeof(double) * initNumberSamples);
    
    double *kernel0 = NULL;
    kernel0  = (double *)fftw_malloc(sizeof(double) * initNumberSamples);
    fkernel0 = (fftw_complex *)fftw_malloc (sizeof(fftw_complex) * nc);
    memset(kernel0, 0, sizeof(double) * initNumberSamples);
    
    double *kernel1 = NULL;
    if (mDerivationsHrf >= 1) {
        kernel1  = (double *)fftw_malloc(sizeof(double) * initNumberSamples);
        fkernel1 = (fftw_complex *)fftw_malloc (sizeof (fftw_complex) * nc);
        memset(kernel1,0,sizeof(double) * initNumberSamples);
    }
    
    double *kernel2 = NULL;
    if (mDerivationsHrf == 2) {
        kernel2  = (double *)fftw_malloc(sizeof(double) * initNumberSamples);
        fkernel2 = (fftw_complex *)fftw_malloc (sizeof (fftw_complex) * nc);
        memset(kernel2,0,sizeof(double) * initNumberSamples);
    }
	
    
    i = 0;
    double t;
    double dt = samplingRateInMs / 1000.0; /* Delta (temporal resolution) in seconds. */
    for (t = 0.0; t < t1; t += dt) {
        if (i >= initNumberSamples) break;//numberSamples
        
        /* Gauss kernel for block designs */
        if (mKernelForBlockDesign == 0) {
            block_kernel[i] = [self xgauss:t :5.0];
        } else if (mKernelForBlockDesign == 1) {
            block_kernel[i] = [self bgamma:t :0.0];
        }
        
        kernel0[i] = [self xgamma:t :0];
        if (mDerivationsHrf >= 1) {
            kernel1[i] = [self deriv1_gamma:t :0.0];
        }
        if (mDerivationsHrf == 2) {
            kernel2[i] = [self deriv2_gamma:t :0.0];
        }
        i++;
    }
    
    /* fft for kernels */
    fftw_plan pkg;
    pkg = fftw_plan_dft_r2c_1d(initNumberSamples, block_kernel, fkernelg, FFTW_ESTIMATE);
    fftw_execute(pkg);
    
    fftw_plan pk0;
    pk0 = fftw_plan_dft_r2c_1d(initNumberSamples, kernel0, fkernel0, FFTW_ESTIMATE);
    fftw_execute(pk0);
    
    fftw_plan pk1;
    if (mDerivationsHrf >= 1) {
        pk1 = fftw_plan_dft_r2c_1d(initNumberSamples, kernel1, fkernel1, FFTW_ESTIMATE);
        fftw_execute(pk1);
    }
    
    fftw_plan pk2;
    if (mDerivationsHrf == 2) {
        pk2 = fftw_plan_dft_r2c_1d(initNumberSamples, kernel2, fkernel2, FFTW_ESTIMATE);
        fftw_execute(pk2);
    }
    
    fftw_free(block_kernel);
    fftw_free(kernel0);
    fftw_free(kernel1);
    fftw_free(kernel2);
    
    return nil;
}

-(NSError*)generateDesign
{
    __block NSError* error = nil;
    
    dispatch_queue_t queue;       /* Global asyn. dispatch queue. */
    queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    
    /* For each event and trial do... */
    dispatch_apply(numberEvents, queue, ^(size_t eventNr) {
        memset(forwardInBuffers[eventNr], 0, sizeof(double) * initNumberSamples);//numberSamples
        
        /* get data */
        int trialcount = 0;
        double t0;
        double h;
        float minTrialDuration = mBlockThreshold;
        
        TrialList* currentTrial;
        currentTrial = trials[eventNr];
        
        while (currentTrial != NULL) {
            trialcount++;
        
            if (currentTrial->trial.duration < minTrialDuration) {
                minTrialDuration = currentTrial->trial.duration;
            }
            t0 = currentTrial->trial.onset;
            double tmax = currentTrial->trial.onset + currentTrial->trial.duration;
            h  = currentTrial->trial.height;
            
            t0 *= 1000.0;
            tmax *= 1000.0;
            
            int k = t0 / samplingRateInMs;
            
            for (double t = t0; t <= tmax; t += samplingRateInMs) {
                if (k >= numberSamples) {
                    break;
                }
                forwardInBuffers[eventNr][k++] += h;
            }
            
            currentTrial = currentTrial->next;
        }
        
        if (trialcount < 1) {
            NSString* errorString = [NSString stringWithFormat:@"No trials in event %d, please re-number event-IDs!", eventNr + 1];
            error = [NSError errorWithDomain:errorString code:EVENT_NUMERATION userInfo:nil];
        }
        if (trialcount < 4) {
            NSLog(@"Warning: too few trials (%d) in event %d. Statistics will be unreliable.",
                  trialcount, eventNr + 1);
        }
        
        /* fft */
        fftw_execute(forwardFFTplans[eventNr]);
        
        int col = eventNr * (mDerivationsHrf + 1);
        
        if (minTrialDuration >= mBlockThreshold) {
            [self Convolve:col 
                          :inverseInBuffers[eventNr]
                          :forwardOutBuffers[eventNr]
                          :inverseOutBuffers[eventNr]
                          :inverseFFTplans[eventNr]
                          :fkernelg];
        } else {
            [self Convolve:col
                          :inverseInBuffers[eventNr]
                          :forwardOutBuffers[eventNr]
                          :inverseOutBuffers[eventNr]
                          :inverseFFTplans[eventNr]
                          :fkernel0];
        }
        
        col++;
        
        if (mDerivationsHrf >= 1) {
            [self Convolve:col
                          :inverseInBuffers[eventNr]
                          :forwardOutBuffers[eventNr]
                          :inverseOutBuffers[eventNr]
                          :inverseFFTplans[eventNr]
                          :fkernel1];
            col++;
        }
        
        if (mDerivationsHrf == 2) {
            [self Convolve:col
                          :inverseInBuffers[eventNr]
                          :forwardOutBuffers[eventNr]
                          :inverseOutBuffers[eventNr]
                          :inverseFFTplans[eventNr]
                          :fkernel2];
        }
    });
    
    return error;
}

-(NSError*)parseInputFile:(NSString *)path
{
    
    int character;
    int trialID    = 0;
    float onset    = 0.0;
    float duration = 0.0;
    float height   = 0.0;
    
    numberTrials = 0;
    numberEvents = 0;
    
    FILE* inFile;
    char* inputFilename = (char*) malloc(sizeof(char) * UINT16_MAX);
    [path getCString:inputFilename maxLength:UINT16_MAX  encoding:NSUTF8StringEncoding];
    
    inFile = fopen(inputFilename, "r");
    char buffer[BUFFER_LENGTH];
    
    while (!feof(inFile)) {
        for (int j = 0; j < BUFFER_LENGTH; j++) {
            buffer[j] = '\0';
        }
        fgets(buffer, BUFFER_LENGTH, inFile);
        if (strlen(buffer) >= 2) {
            
            // TODO: Maybe remove this check
            if (![self test_ascii:((int) buffer[0])]) {
                NSLog(@" input file must be a text file");
            }
            
            if (buffer[0] != '%' && buffer[0] != '#') {
                /* remove non-alphanumeric characters */
                for (int j = 0; j < strlen(buffer); j++) {
                    character = (int) buffer[j];
                    if (!isgraph(character) && buffer[j] != '\n' && buffer[j] != '\r' && buffer[j] != '\0') {
                        buffer[j] = ' ';
                    }
                    
                    /* remove tabs */
                    if (buffer[j] == '\v') {
                        buffer[j] = ' ';
                    }
                    if (buffer[j] == '\t') {
                        buffer[j] = ' ';
                    }
                }
                
                if (sscanf(buffer, "%d %f %f %f", &trialID, &onset, &duration, &height) != 4) {

                    NSString* errorString = 
                        [NSString stringWithFormat:
                            @"Illegal design file input format (at line %d)! Expected format: one entry per line and columns separated by tabs.", numberTrials + 1];
                    return [NSError errorWithDomain:errorString code:ILLEGAL_INPUT_FORMAT userInfo:nil];
                    
                }
                
                if (duration < 0.5 && duration >= -0.0001) {
                    duration = 0.5;
                }

                Trial newTrial;
                newTrial.id       = trialID;
                newTrial.onset    = onset;
                newTrial.duration = duration;
                newTrial.height   = height;
                
                TrialList* newListEntry;
                newListEntry = (TrialList*) malloc(sizeof(TrialList));
                *newListEntry = TRIALLIST_INIT;
                newListEntry->trial = newTrial;
                
                if (trials[trialID - 1] == NULL) {
                    trials[trialID - 1] = newListEntry;
                    numberEvents++;
                } else {
                    [self tl_append:trials[trialID - 1] :newListEntry];
                }
                
                numberTrials++;
            }
        }
    }
    fclose(inFile);  
    free(inputFilename);
    
    return nil;
}

-(NSError*)writeDesignFile:(NSString*) path 
{
    VImage outDesign = NULL;
    outDesign = VCreateImage(1, numberTimesteps, mNumberRegressors, VFloatRepn);
    
    VSetAttr(VImageAttrList(outDesign), "modality", NULL, VStringRepn, "X");
    VSetAttr(VImageAttrList(outDesign), "name", NULL, VStringRepn, "X");
    VSetAttr(VImageAttrList(outDesign), "repetition_time", NULL, VLongRepn, (VLong) mRepetitionTimeInMs);
    VSetAttr(VImageAttrList(outDesign), "ntimesteps", NULL, VLongRepn, (VLong) numberTimesteps);
    
    VSetAttr(VImageAttrList(outDesign), "derivatives", NULL, VShortRepn, mDerivationsHrf);
    
    // evil: Copy&Paste from initDesign()
    static float delay = 6.0;              
    static float understrength = 0.35;
    static float undershoot = 12.0;
    char buf[BUFFER_LENGTH];
    
    VSetAttr(VImageAttrList(outDesign), "delay", NULL, VFloatRepn, delay);
    VSetAttr(VImageAttrList(outDesign), "undershoot", NULL, VFloatRepn, undershoot);
    sprintf(buf, "%.3f", understrength);
    VSetAttr(VImageAttrList(outDesign), "understrength", NULL, VStringRepn, &buf);
    
    VSetAttr(VImageAttrList(outDesign), "nsessions", NULL, VShortRepn, (VShort) 1);
    VSetAttr(VImageAttrList(outDesign), "designtype", NULL, VShortRepn, (VShort) 1);
    
    for (int col = 0; col < mNumberRegressors; col++) {
        for (int ts = 0; ts < numberTimesteps; ts++) {
//			if ((mDesign[col][ts] < 0.000000000000001 && mDesign[col][ts] > -0.000000000000001) || ts < 7) {
//				VPixel(outDesign, 0, ts, col, VFloat) = (VFloat) 0.0;
//			} else {
				VPixel(outDesign, 0, ts, col, VFloat) = (VFloat) mDesign[col][ts];
//			}
//			if (col < 1 && (ts > 360 && ts < 391)){
//				NSLog(@"%.20f", mDesign[col][ts]);
//			}
        }
    }
    
    
    VAttrList out_list = NULL;                         
    out_list = VCreateAttrList();
    VAppendAttr(out_list, "image", NULL, VImageRepn, outDesign);
    
    // Numbers taken from Plot_gamma()
    int ncols = (int) (28.0 / 0.2);
    int nrows = mDerivationsHrf + 2;
    VImage plot_image = NULL;
    plot_image = VCreateImage(1, nrows, ncols, VFloatRepn);
    float** plot_image_raw = NULL;
    plot_image_raw = [self Plot_gamma];
    
    for (int col = 0; col < ncols; col++) {
        for (int row = 0; row < nrows; row++) {
            VPixel(plot_image, 0, row, col, VFloat) = (VFloat) plot_image_raw[col][row];
//			if (col < 10 && row < 10){
//				NSLog(@"%.50lf", (VFloat) plot_image_raw[col][row]);
//			}
        }
    }
	

    VAppendAttr(out_list, "plot_gamma", NULL, VImageRepn, plot_image);
    
    char* outputFilename = (char*) malloc(sizeof(char) * UINT16_MAX);
    [path getCString:outputFilename maxLength:UINT16_MAX  encoding:NSUTF8StringEncoding];
    FILE *out_file = fopen(outputFilename, "w"); //fopen("/tmp/testDesign.v", "w");

    if (!VWriteFile(out_file, out_list)) {
        return [NSError errorWithDomain:@"Writing output design image failed." code:WRITE_OUTPUT userInfo:nil];
    }
    
    fclose(out_file);
    free(outputFilename);
    
    return nil;
}

-(Complex)complex_mult:(Complex) a
                      :(Complex) b
{
    Complex w;
    w.re = a.re * b.re  -  a.im * b.im;
    w.im = a.re * b.im  +  a.im * b.re;
    return w;
}

/*
 * Glover kernel, gamma function
 */
-(double)xgamma:(double) xx
               :(double) t0
{
    double scale = 20.0; // nobody knows where it comes from
    
    double x = xx - t0;
    if (x < 0 || x > 50) {
        return 0;
    }
    
    double d1 = a1 * b1;
    double d2 = a2 * b2;
    
    double y1 = pow(x / d1, a1) * exp(-(x - d1) / b1);
    double y2 = pow(x / d2, a2) * exp(-(x - d2) / b2);
    
    double y = y1 - cc * y2;
    y /= scale;
    return y;
}

/*
 * Glover kernel, gamma function, parameters changed for block designs
 */
-(double)bgamma:(double) xx
               :(double) t0
{
    double x;
    double y;
    double scale=120;
    
    double y1;
    double y2;
    double d1;
    double d2;
    
    double aa1 = 6;     
    double bb1 = 0.9;
    double aa2 = 12;
    double bb2 = 0.9;
    double cx  = 0.1;
    
    x = xx - t0;
    if (x < 0 || x > 50) {
        return 0;
    }
    
    d1 = aa1 * bb1;
    d2 = aa2 * bb2;
    
    y1 = pow(x / d1, aa1) * exp(-(x - d1) / bb1);
    y2 = pow(x / d2, aa2) * exp(-(x - d2) / bb2);
    
    y = y1 - cx * y2;
    y /= scale;
    return y;
}

/* First derivative. */
-(double)deriv1_gamma:(double) x 
                     :(double) t0
{
    double d1;
    double d2;
    double y1;
    double y2;
    double y;
    double xx;
    
    double scale = 20.0;
    
    xx = x - t0;
    if (xx < 0 || xx > 50) {
        return 0;
    }
    
    d1 = a1 * b1;
    d2 = a2 * b2;
    
    y1 = pow(d1, -a1) * a1 * pow(xx, (a1 - 1.0)) * exp(-(xx - d1) / b1) 
                - (pow((xx / d1), a1) * exp(-(xx - d1) / b1)) / b1;
    
    y2 = pow(d2, -a2) * a2 * pow(xx, (a2 - 1.0)) * exp(-(xx - d2) / b2) 
                - (pow((xx / d2), a2) * exp(-(xx - d2) / b2)) / b2;
    
    y = y1 - cc * y2;
    y /= scale;
    
    return y;
}

/* Second derivative. */
-(double)deriv2_gamma:(double) x0
                     :(double) t0
{
    double d1;
    double d2;
    double y1;
    double y2;
    double y3;
    double y4;
    double y;
    double x;
    
    double scale=20.0;
    
    x = x0 - t0;
    if (x < 0 || x > 50) {
        return 0;
    }
    
    d1 = a1 * b1;
    d2 = a2 * b2;
    
    y1 = pow(d1, -a1) * a1 * (a1 - 1) * pow(x, a1 - 2) * exp(-(x - d1) / b1) 
                - pow(d1, -a1) * a1 * pow(x, (a1 - 1)) * exp(-(x - d1) / b1) / b1;
    y2 = pow(d1, -a1) * a1 * pow(x, a1 - 1) * exp(-(x - d1) / b1) / b1
                - pow((x / d1), a1) * exp(-(x - d1) / b1) / (b1 * b1);
    y1 = y1 - y2;
    
    y3 = pow(d2, -a2) * a2 * (a2 - 1) * pow(x, a2 - 2) * exp(-(x - d2) / b2) 
                - pow(d2, -a2) * a2 * pow(x, (a2 - 1)) * exp(-(x - d2) / b2) / b2;
    y4 = pow(d2, -a2) * a2 * pow(x, a2 - 1) * exp(-(x - d2) / b2) / b2
                - pow((x / d2), a2) * exp(-(x - d2) / b2) / (b2 * b2);
    y2 = y3 - y4;
    
    y = y1 - cc * y2;
    y /= scale;
    
    return y;
}

/* Gaussian function. */
-(double)xgauss:(double)x0
               :(double)t0
{
    double sigma = 1.0;
    double scale = 20.0;
    double x;
    double y;
    double z;
    double a=2.506628273;
    
    x = (x0 - t0);
    z = x / sigma;
    y = exp((double) - z * z * 0.5) / (sigma * a);
    y /= scale;
    return y;
}

-(float**)Plot_gamma
{
    double y0;
    double y1;
    double y2;
    double t0 = 0.0;
    double step = 0.2;
    
    int ncols = (int) (28.0 / step);
    int nrows = mDerivationsHrf + 2;
    
    float** dest = (float**) malloc(sizeof(float*) * ncols);
    for (int col = 0; col < ncols; col++) {
        
        dest[col] = (float*) malloc(sizeof(float) * nrows);
        for (int row = 0; row < nrows; row++) {
            dest[col][row] = 0.0;
        }
    }
    
    int j = 0;
    for (double x = 0.0; x < 28.0; x += step) {
        if (j >= ncols) {
            break;
        }
        y0 = [self xgamma:x :t0];
        y1 = [self deriv1_gamma:x :t0];
        y2 = [self deriv2_gamma:x :t0];

        dest[j][0] = x;
        dest[j][1] = y0;
        if (mDerivationsHrf > 0) {
            dest[j][2] = y1;
        }
        if (mDerivationsHrf > 1) {
            dest[j][3] = y2;
        }
        j++;
    }
    
    return dest;
}

-(BOOL)test_ascii:(int)val
{
    if (val >= 'a' && val <= 'z') return YES;
    if (val >= 'A' && val <= 'Z') return YES;
    if (val >= '0' && val <= '9') return YES;
    if (val ==  ' ')              return YES;
    if (val == '\0')              return YES;
    if (val == '\n')              return YES;
    if (val == '\r')              return YES;
    if (val == '\t')              return YES;
    if (val == '\v')              return YES;
    
    return NO;
}

-(void)Convolve:(int)col
               :(fftw_complex *)local_nbuf
               :(fftw_complex *)forwardOutBuffer
               :(double *)inverseOutBuffer
               :(fftw_plan)planInverseFFT
               :(fftw_complex *)fkernel
{
    Complex a;
    Complex b;
    Complex c;
    
    int nc = (initNumberSamples / 2) + 1;//numberSamples
    
    /* convolution */
    int j;
    for (j = 0; j < nc; j++) {
        a.re = forwardOutBuffer[j][0];
        a.im = forwardOutBuffer[j][1];
        b.re = fkernel[j][0];
        b.im = fkernel[j][1];
        c = [self complex_mult:a :b];    
        local_nbuf[j][0] = c.re;
        local_nbuf[j][1] = c.im;
    }
    
    /* inverse fft */
    fftw_execute(planInverseFFT);
    
    /* scaling */
    for (j = 0; j < initNumberSamples; j++) {//numberSamples
        inverseOutBuffer[j] /= (double) initNumberSamples;//numberSamples
    }
    
    /* sampling */
    for (int timestep = 0; timestep < numberTimesteps; timestep++) {
        j = (int) (xx[timestep] / samplingRateInMs + 0.5);
        
        if (j >= 0 && j < numberSamples) {//numberSamples
            mDesign[col][timestep] = inverseOutBuffer[j];
        }
    }
}

-(void)tl_append:(TrialList*)head
                :(TrialList*)newLast
{
    TrialList* current;
    current = head;
    while (current->next != NULL) {
        current = current->next;
    }
    current->next = newLast; 
}


-(NSNumber*)getValueFromExplanatoryVariable:(int)cov 
                                 atTimestep:(int)t 
{
    NSNumber *value = nil;
    if (cov < mNumberRegressors) {
        if (mDesign != NULL) {
            if (IMAGE_DATA_FLOAT == imageDataType){
                value = [NSNumber numberWithFloat:mDesign[cov][t]];
            } else {
                NSLog(@"Cannot identify type of design image - no float");
            }
        } else {
            NSLog(@"%@: generateDesign has not been called yet! (initial design information NULL)", self);
        }
    } else {
        int covIndex = cov - mNumberRegressors;
        value = [NSNumber numberWithFloat:mCovariates[covIndex][t]];
    }
    
    return value;
}

-(void)setRegressor:(TrialList *)regressor
{
    free(trials[regressor->trial.id - 1]);
    trials[regressor->trial.id - 1] = NULL;
    trials[regressor->trial.id - 1] = regressor;
    
    [self generateDesign];
}

-(void)setRegressorTrial:(Trial)trial 
{

	//TODO: eine Logik falls sich Bereiche überschneiden in einem Eventtyp
	TrialList* newListEntry;
	newListEntry = (TrialList*) malloc(sizeof(TrialList));
	*newListEntry = TRIALLIST_INIT;
	newListEntry->trial = trial;
	
	if (trials[trial.id - 1] == NULL) {
		trials[trial.id - 1] = newListEntry;
	} else {
		[self tl_append:trials[trial.id - 1] :newListEntry];
	}
}

-(void)setCovariate:(float*)covariate forCovariateID:(int)covID
{
    if (mCovariates != NULL) {
        free(mCovariates[covID - 1]);
        mCovariates[covID - 1] = NULL;
        mCovariates[covID - 1] = covariate;
    } else {
        NSLog(@"Could not set covariate values for CovariateID %d because number of covariates is 0.", covID);
    }

}

-(void)setCovariateValue:(float)value forCovariateID:(int)covID atTimestep:(int)timestep
{
    if (mCovariates != NULL) {
        mCovariates[covID - 1][timestep] = value;
    } else {
        NSLog(@"Could not set covariate value %f for CovariateID %d at timestep %d because number of covariates is 0.", value, covID, timestep);
    }
}

-(void)dealloc
{
    for (int col = 0; col < mNumberRegressors; col++) {
        free(mDesign[col]);
    }
    free(mDesign);
    
    if (mCovariates != NULL) {
        for (int cov = 0; cov < mNumberCovariates; cov++) {
            free(mCovariates[cov]);
        }
        free(mCovariates);
    }
    
    free(xx);
    
    for (int eventNr = 0; eventNr < numberEvents; eventNr++) {
        fftw_free(forwardInBuffers[eventNr]);
        fftw_free(forwardOutBuffers[eventNr]);
        fftw_free(inverseInBuffers[eventNr]);
        fftw_free(inverseOutBuffers[eventNr]);
        
        TrialList* node;
        TrialList* tmp;
        node = trials[eventNr];
        while (node != NULL) {
            tmp = node;
            node = node -> next;
            free(tmp);
        }
    }
    
    free(trials);
    free(forwardInBuffers);
    fftw_free(forwardOutBuffers);
    fftw_free(inverseInBuffers);
    free(inverseOutBuffers);
    fftw_free(fkernelg);
    fftw_free(fkernel0);
    fftw_free(fkernel1);
    fftw_free(fkernel2);
    
    free(forwardFFTplans);
    free(inverseFFTplans);

    [super dealloc];
}

@end
