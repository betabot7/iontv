/*-
 * WSGeneratedObj.h
 *
 *	Version 0.10
 *
 * This class was automatically generated by WSMakeStubs, part of the
 * WebServicesCore framework.
 * It implements a generic object layer on top of the primitive WebServicesCore API.
 *
 */

#ifndef __WSGeneratedObj__
#define __WSGeneratedObj__

#include <CoreServices/CoreServices.h>
#include <Foundation/Foundation.h>

@interface WSGeneratedObj : NSObject {
	WSMethodInvocationRef fRef;
	NSDictionary* fResult;
        NSDictionary* fParams;
        NSArray*      fParamOrder;
	id fAsyncTarget;
	SEL fAsyncSelector;
};

// For Asynchronous processing, you can specify a callback
// and schedule this invocation on a runloop.
// Note that making any call other than isComplete
// after the invocation in scheduled will block until the invocation completes and
// the callback will not be called.
// The selector signature is "invocationResponse:" and is passed a reference
// to this object.
- (void) setCallBack:(id) target selector:(SEL) selector;
- (void) scheduleOnRunLoop:(NSRunLoop*) runloop mode:(NSString*) mode;
- (void) unscheduleFromRunLoop:(NSRunLoop*) runloop mode:(NSString*) mode;

	// Check if the invocation is complete - that is,
	// if the result has been obtained.
- (BOOL) isComplete;

	// Return the Result object.  If the result hasn't completed, this will block
- (NSDictionary*) getResultDictionary;

	// Returns true if the Result is a fault.  If the result hasn't completed, this will block.
- (BOOL) isFault;

	// Returns the return Value associated with this method.
	// if the subclass overrides this, it will be the value
	// specified by the WSDL.  If the result hasn't completed, this
	// will block.
- (id) getValue;

	// handleError gets called when the WebServices framework returns an error that
	// leaves us without a valid result or fault.
- (void) handleError:(NSString*) stubError errorString:(NSString*) errorString errorDomain:(int) errorDomain errorNumber:(int) errorNumber;

	/*
	 * Implementation Details
	 */

	// if you need to add extra headers to outgoing messages,
	// you can override this function to do so when
	// we add the SOAPAction header.  You should produce
	// a dictionary containing these keys as well...
- (NSDictionary*) copyHeaderDictionary:(int) extraTypeCount extraVals:(NSString**) extraVals extraKeys:(NSString**) extraKeys;

	// Return (possibly creating) the WSMethodInvocationRef
- (WSMethodInvocationRef) getRef;

	// Private implementation methods
- (WSMethodInvocationRef) genCreateInvocationRef;
- (void) setParameters:(int) count values:(id*) values names:(NSString**) names;
- (WSMethodInvocationRef) createInvocationRef:(NSString*) endpoint
								   methodName:(NSString*) methodName
								   protocol:(NSString*) protocol
									    style:(NSString*) style
								   soapAction:(NSString*) soapAction
							  methodNamespace:(NSString*) methodNamespace;

@end;

#endif

