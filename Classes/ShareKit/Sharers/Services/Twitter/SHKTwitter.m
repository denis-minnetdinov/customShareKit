//
//  SHKTwitter.m
//  ShareKit
//
//  Created by Nathan Weiner on 6/21/10.

//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//
//

// TODO - SHKTwitter supports offline sharing, however the url cannot be shortened without an internet connection.  Need a graceful workaround for this.


#import "SHKConfiguration.h"
#import "SHKTwitter.h"
#import "JSONKit.h"
#import "SHKXMLResponseParser.h"
#import "SHKiOS5Twitter.h"
#import "NSMutableDictionary+NSNullsToEmptyStrings.h"
#import <Twitter/Twitter.h>
#import <Accounts/Accounts.h>

static NSString *const kSHKTwitterUserInfo=@"kSHKTwitterUserInfo";

@interface SHKTwitter ()

- (BOOL)prepareItem;
- (BOOL)shortenURL;
- (void)shortenURLFinished:(SHKRequest *)aRequest;
- (BOOL)validateItemAfterUserEdit;
- (void)handleUnsuccessfulTicket:(NSData *)data;
- (BOOL)twitterFrameworkAvailable;

@end

@implementation SHKTwitter
@synthesize xAuth, iOS5twitterAccount, iOS5twitterAccountsArray;

- (id)init
{
	if (self = [super init])
	{	
		// OAUTH		
		self.consumerKey = SHKCONFIG(twitterConsumerKey);		
		self.secretKey = SHKCONFIG(twitterSecret);
 		self.authorizeCallbackURL = [NSURL URLWithString:SHKCONFIG(twitterCallbackUrl)];// HOW-TO: In your Twitter application settings, use the "Callback URL" field.  If you do not have this field in the settings, set your application type to 'Browser'.
		
		// XAUTH
		self.xAuth = [SHKCONFIG(twitterUseXAuth) boolValue]?YES:NO;
		
		
		// -- //
		
		
		// You do not need to edit these, they are the same for everyone
		self.authorizeURL = [NSURL URLWithString:@"https://api.twitter.com/oauth/authorize"];
		self.requestURL = [NSURL URLWithString:@"https://api.twitter.com/oauth/request_token"];
		self.accessURL = [NSURL URLWithString:@"https://api.twitter.com/oauth/access_token"];
        
        self.iOS5twitterAccount = [[[ACAccount alloc] init] autorelease];
        self.iOS5twitterAccountsArray = [[[NSArray alloc] init] autorelease];
	}	
	return self;
}


#pragma mark -
#pragma mark Configuration : Service Defination

+ (NSString *)sharerTitle
{
	return @"Twitter";
}

+ (BOOL)canShareURL
{
	return YES;
}

+ (BOOL)canShareText
{
	return YES;
}

// TODO use img.ly to support this
+ (BOOL)canShareImage
{
	return YES;
}

+ (BOOL)canGetUserInfo
{
	return YES;
}

#pragma mark -
#pragma mark Configuration : Dynamic Enable

- (BOOL)shouldAutoShare
{
    return YES;
}

#pragma mark -
#pragma mark Commit Share

- (void)share {
	
	if ([self twitterFrameworkAvailable]) {
		
		SHKSharer *sharer =[SHKiOS5Twitter shareItem:self.item];
        sharer.quiet = self.quiet;
        sharer.shareDelegate = self.shareDelegate;
		[SHKTwitter logout];//to clean credentials - we will not need them anymore
		return;
	}
	
	BOOL itemPrepared = [self prepareItem];
	
	//the only case item is not prepared is when we wait for URL to be shortened on background thread. In this case [super share] is called in callback method
	if (itemPrepared) {
		[super share];
	}
}

#pragma mark -

- (BOOL)twitterFrameworkAvailable {
	
    if ([SHKCONFIG(forcePreIOS5TwitterAccess) boolValue])
    {
        return NO;
    }
    
	if (NSClassFromString(@"TWTweetComposeViewController")) {
		return YES;
	}
	
	return NO;
}

- (BOOL)prepareItem {
	
	BOOL result = YES;
	
	if (item.shareType == SHKShareTypeURL)
	{
		BOOL isURLAlreadyShortened = [self shortenURL];
		result = isURLAlreadyShortened;
		
	}
    
    NSString *hashtags = [self tagStringJoinedBy:@" " allowedCharacters:[NSCharacterSet alphanumericCharacterSet] tagPrefix:@"#"];
    
    NSString *tweetBody = [NSString stringWithFormat:@"%@%@%@",(item.shareType == SHKShareTypeText ? item.text : item.title ),([hashtags length] ? @" " : @""), hashtags];
	
    [item setCustomValue:tweetBody forKey:@"status"];
    
	return result;
}

#pragma mark -
#pragma mark Authorization

- (BOOL)isAuthorized
{		
	if ([self twitterFrameworkAvailable]) {
		[SHKTwitter logout];
		return NO; 
	}
	return [self restoreAccessToken];
}

- (void)promptAuthorization
{	
	if ([self twitterFrameworkAvailable]) {
        
        // Create an account store object.
        ACAccountStore *accountStore = [[ACAccountStore alloc] init];
        
        // Create an account type that ensures Twitter accounts are retrieved.
        ACAccountType *accountType = [accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
		
        // Request access from the user to use their Twitter accounts.
        [accountStore requestAccessToAccountsWithType:accountType withCompletionHandler:^(BOOL granted, NSError *error) {
           if(granted)
           {
               // Get the list of Twitter accounts.
               self.iOS5twitterAccountsArray = [NSArray arrayWithArray:[accountStore accountsWithAccountType:accountType]];
               
               // For the sake of brevity, we'll assume there is only one Twitter account present.
               // You would ideally ask the user which account they want to tweet from, if there is more than one Twitter account present.
               if ([self.iOS5twitterAccountsArray count] == 1) {
                   self.iOS5twitterAccount = [iOS5twitterAccountsArray objectAtIndex:0];
                   NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:[iOS5twitterAccount username], @"screen_name", [[iOS5twitterAccount valueForKey:@"properties"] valueForKey:@"user_id"], @"id", nil];
                   [[NSUserDefaults standardUserDefaults] setObject:userInfo forKey:kSHKTwitterUserInfo];
                   [super authDidFinish:YES];
               }
               else
               {
                   if ([self.iOS5twitterAccountsArray count] > 0) {
                       dispatch_sync(dispatch_get_main_queue(), ^{
                           UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Twitter accounts"
                                                                           message:@"Choose Twitter account to connect"
                                                                          delegate:self
                                                                 cancelButtonTitle:@"Cancel" otherButtonTitles:nil];
                           for (ACAccount *account in iOS5twitterAccountsArray)
                           {
                               NSString *userName = [NSString stringWithFormat:@"@%@", account.username];
                               [alert addButtonWithTitle:userName];
                           }
                           [alert show];
                           [alert release];
                       });
                       
                   }
                   else
                   {
                       dispatch_sync(dispatch_get_main_queue(), ^{
                           UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"No Twitter Accounts"
                                                                           message:@"There are no Twitter accounts configured. You can add or create a Twitter account in Settings."
                                                                          delegate:nil
                                                                 cancelButtonTitle:@"OK"
                                                                 otherButtonTitles:nil];
                           [alert show];
                           [alert release];
                           self.iOS5twitterAccount = nil;
                           self.iOS5twitterAccountsArray = nil;
                           [super authDidFinish:NO];
                       });
                   }
               }
           }
           else
           {
               [super authDidFinish:NO];
           }
        }];
        
        SHKLog(@"There is no need to authorize when we use iOS Twitter framework");
		return;
	}
	
	if (xAuth)
		[super authorizationFormShow]; // xAuth process
	
	else
		[super promptAuthorization]; // OAuth process		
}

+ (void)logout {
	
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:kSHKTwitterUserInfo];
	[super logout];    
}

#pragma mark xAuth

+ (NSString *)authorizationFormCaption
{
	return SHKLocalizedString(@"Create a free account at %@", @"Twitter.com");
}

+ (NSArray *)authorizationFormFields
{
	if ([SHKCONFIG(twitterUsername) isEqualToString:@""])
		return [super authorizationFormFields];
	
	return [NSArray arrayWithObjects:
			  [SHKFormFieldSettings label:SHKLocalizedString(@"Username") key:@"username" type:SHKFormFieldTypeTextNoCorrect start:nil],
			  [SHKFormFieldSettings label:SHKLocalizedString(@"Password") key:@"password" type:SHKFormFieldTypePassword start:nil],
			  [SHKFormFieldSettings label:SHKLocalizedString(@"Follow %@", SHKCONFIG(twitterUsername)) key:@"followMe" type:SHKFormFieldTypeSwitch start:SHKFormFieldSwitchOn],			
			  nil];
}

- (void)authorizationFormValidate:(SHKFormController *)form
{
	self.pendingForm = form;
	[self tokenAccess];
}

- (void)tokenAccessModifyRequest:(OAMutableURLRequest *)oRequest
{	
	if (xAuth)
	{
		NSDictionary *formValues = [pendingForm formValues];
		
		OARequestParameter *username = [[[OARequestParameter alloc] initWithName:@"x_auth_username"
																								 value:[formValues objectForKey:@"username"]] autorelease];
		
		OARequestParameter *password = [[[OARequestParameter alloc] initWithName:@"x_auth_password"
																								 value:[formValues objectForKey:@"password"]] autorelease];
		
		OARequestParameter *mode = [[[OARequestParameter alloc] initWithName:@"x_auth_mode"
																							value:@"client_auth"] autorelease];
		
		[oRequest setParameters:[NSArray arrayWithObjects:username, password, mode, nil]];
	}
}

- (void)tokenAccessTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data 
{
	if (xAuth) 
	{
		if (ticket.didSucceed)
		{
			[item setCustomValue:[[pendingForm formValues] objectForKey:@"followMe"] forKey:@"followMe"];
			[pendingForm close];
		}
		
		else
		{
			NSString *response = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
			
			SHKLog(@"tokenAccessTicket Response Body: %@", response);
			
			[self tokenAccessTicket:ticket didFailWithError:[SHK error:response]];
			return;
		}
	}
	
	[super tokenAccessTicket:ticket didFinishWithData:data];		
}


#pragma mark -
#pragma mark UI Implementation

- (void)show
{
	if (item.shareType == SHKShareTypeURL)
	{
		[self showTwitterForm];
	}
	
	else if (item.shareType == SHKShareTypeImage)
	{
		[self showTwitterForm];
	}
	
	else if (item.shareType == SHKShareTypeText)
	{
		[self showTwitterForm];
	}
	
	else if (item.shareType == SHKShareTypeUserInfo)
	{
		[self setQuiet:YES];
		[self tryToSend];
	}
}

- (void)showTwitterForm
{
	SHKCustomFormControllerLargeTextField *rootView = [[SHKCustomFormControllerLargeTextField alloc] initWithNibName:nil bundle:nil delegate:self];	
	
	rootView.text = [item customValueForKey:@"status"];
	rootView.maxTextLength = 140;
	rootView.image = item.image;
	rootView.imageTextLength = 25;
	
	self.navigationBar.tintColor = SHKCONFIG_WITH_ARGUMENT(barTintForView:,self);
	
	[self pushViewController:rootView animated:NO];
	[rootView release];
	
	[[SHK currentHelper] showViewController:self];	
}

- (void)sendForm:(SHKCustomFormControllerLargeTextField *)form
{	
	[item setCustomValue:form.textView.text forKey:@"status"];
	[self tryToSend];
}

#pragma mark -

- (BOOL)shortenURL
{	
	NSString *bitLyLogin = SHKCONFIG(bitLyLogin);
	NSString *bitLyKey = SHKCONFIG(bitLyKey);
	BOOL bitLyConfigured = [bitLyLogin length] > 0 && [bitLyKey length] > 0;
	
	if (bitLyConfigured == NO || ![SHK connected])
	{
		[item setCustomValue:[NSString stringWithFormat:@"%@ %@", item.title ? item.title : item.text, [item.URL.absoluteString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] forKey:@"status"];
		return YES;
	}
	
	if (!quiet)
		[[SHKActivityIndicator currentIndicator] displayActivity:SHKLocalizedString(@"Shortening URL...")];
	
	self.request = [[[SHKRequest alloc] initWithURL:[NSURL URLWithString:[NSMutableString stringWithFormat:@"http://api.bit.ly/v3/shorten?login=%@&apikey=%@&longUrl=%@&format=txt",
																		  bitLyLogin,
																		  bitLyKey,																		  
																		  SHKEncodeURL(item.URL)
																		  ]]
											 params:nil
										   delegate:self
								 isFinishedSelector:@selector(shortenURLFinished:)
											 method:@"GET"
										  autostart:YES] autorelease];
    return NO;
}

- (void)shortenURLFinished:(SHKRequest *)aRequest
{
	[[SHKActivityIndicator currentIndicator] hide];
	
	NSString *result = [[aRequest getResult] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	
	if (!aRequest.success || result == nil || [NSURL URLWithString:result] == nil)
	{
		// TODO - better error message
		[[[[UIAlertView alloc] initWithTitle:SHKLocalizedString(@"Shorten URL Error")
											  message:SHKLocalizedString(@"We could not shorten the URL.")
											 delegate:nil
								 cancelButtonTitle:SHKLocalizedString(@"Continue")
								 otherButtonTitles:nil] autorelease] show];
        
        NSString *currentStatus = [item customValueForKey:@"status"];
        
		[item setCustomValue:[NSString stringWithFormat:@"%@ %@", currentStatus, [item.URL.absoluteString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] forKey:@"status"];
	}
	
	else
	{		
		///if already a bitly login, use url instead
		if ([result isEqualToString:@"ALREADY_A_BITLY_LINK"])
			result = [item.URL.absoluteString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        
        NSString *currentStatus = [item customValueForKey:@"status"];
		
		[item setCustomValue:[NSString stringWithFormat:@"%@ %@", currentStatus, result] forKey:@"status"];
	}
	
	[super share];
}


#pragma mark -
#pragma mark Share API Methods

- (BOOL)validateItem
{
	if (self.item.shareType == SHKShareTypeUserInfo) {
		return YES;
	}
	
	NSString *status = [item customValueForKey:@"status"];
	return status != nil;
}

- (BOOL)validateItemAfterUserEdit {
	
	BOOL result = NO;
	
	BOOL isValid = [self validateItem];    
	NSString *status = [item customValueForKey:@"status"];
	
	if (isValid && status.length <= 140) {
		result = YES;
	}
	
	return result;
}

- (BOOL)send
{	
	// Check if we should send follow request too
	if (xAuth && [item customBoolForSwitchKey:@"followMe"])
		[self followMe];	
	
	if (![self validateItemAfterUserEdit])
		return NO;
	
	switch (item.shareType) {
			
		case SHKShareTypeImage:            
			[self sendImage];
			break;
			
		case SHKShareTypeUserInfo:            
			[self sendUserInfo];
			break;
			
		default:
			[self sendStatus];
			break;
	}
	
	// Notify delegate
	[self sendDidStart];
	
	return YES;
}

- (void)sendUserInfo {
	
	OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"https://api.twitter.com/1/account/verify_credentials.json"]
																						 consumer:consumer
																							 token:accessToken
																							 realm:nil
																			 signatureProvider:nil];	
	[oRequest setHTTPMethod:@"GET"];
	OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
																													  delegate:self
																										  didFinishSelector:@selector(sendUserInfo:didFinishWithData:)
																											 didFailSelector:@selector(sendUserInfo:didFailWithError:)];		
	[fetcher start];
	[oRequest release];
}

- (void)sendUserInfo:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data 
{	
	if (ticket.didSucceed) {
		
		NSError *error = nil;
		NSMutableDictionary *userInfo;
		Class serializator = NSClassFromString(@"NSJSONSerialization");
		if (serializator) {
			userInfo = [serializator JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
		} else {
			userInfo = [[JSONDecoder decoder] mutableObjectWithData:data error:&error];
		}    
		
		if (error) {
			SHKLog(@"Error when parsing json twitter user info request:%@", [error description]);
		}
		
		[userInfo convertNSNullsToEmptyStrings];
        NSLog(@"%@", userInfo);
		[[NSUserDefaults standardUserDefaults] setObject:userInfo forKey:kSHKTwitterUserInfo];
		
		[self sendDidFinish];
		
	} else {
		
		[self handleUnsuccessfulTicket:data];
	}
}

- (void)sendUserInfo:(OAServiceTicket *)ticket didFailWithError:(NSError*)error
{
	[self sendDidFailWithError:error];
}

- (void)sendStatus
{
	OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"https://api.twitter.com/1/statuses/update.json"]
																						 consumer:consumer
																							 token:accessToken
																							 realm:nil
																			 signatureProvider:nil];

	[oRequest setHTTPMethod:@"POST"];
	
	OARequestParameter *statusParam = [[OARequestParameter alloc] initWithName:@"status"
																								value:[item customValueForKey:@"status"]];
	NSArray *params = [NSArray arrayWithObjects:statusParam, nil];
	[oRequest setParameters:params];
	[statusParam release];
	
	OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
																													  delegate:self
																										  didFinishSelector:@selector(sendStatusTicket:didFinishWithData:)
																											 didFailSelector:@selector(sendStatusTicket:didFailWithError:)];	
	
	[fetcher start];
	[oRequest release];
}

- (void)sendStatusTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data 
{	
	// TODO better error handling here
	if (ticket.didSucceed) 
		[self sendDidFinish];
	
	else
	{		
		[self handleUnsuccessfulTicket:data];
	}
}

- (void)sendStatusTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error
{
	[self sendDidFailWithError:error];
}


- (void)sendImage {
    NSString *twitterSecret = [[SHKConfiguration sharedInstance] configurationValue:@"twitterSecret" withObject:nil];
    NSString *twitPicKey = [[SHKConfiguration sharedInstance] configurationValue:@"twitPicKey" withObject:nil];
    
    NSURL *url = [NSURL URLWithString:@"http://api.twitpic.com/1/uploadAndPost.json"];
	ASIFormDataRequest *req = [ASIFormDataRequest requestWithURL:url];
	[req addPostValue:twitPicKey forKey:@"key"];
	[req addPostValue:consumerKey forKey:@"consumer_token"];
	[req addPostValue:twitterSecret forKey:@"consumer_secret"];
	[req addPostValue:accessToken.key forKey:@"oauth_token"];
	[req addPostValue:accessToken.secret forKey:@"oauth_secret"];
	[req addPostValue:[item customValueForKey:@"status"] forKey:@"message"];
    [req setStartedBlock:^{
        [self sendDidStart];
    }];
    [req setFailedBlock:^{
        [self sendDidFailWithError:req.error];
    }];
    [req setCompletionBlock:^{
        [self sendDidFinish];
    }];
    
	[req addData:UIImageJPEGRepresentation([item image], 0.8) forKey:@"media"];
	req.requestMethod = @"POST";
	[req startAsynchronous];
}

- (void)sendImageTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data {
	// TODO better error handling here
	// SHKLog([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
	
	if (ticket.didSucceed) {
		// Finished uploading Image, now need to posh the message and url in twitter
		NSString *dataString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		NSRange startingRange = [dataString rangeOfString:@"<url>" options:NSCaseInsensitiveSearch];
		//SHKLog(@"found start string at %d, len %d",startingRange.location,startingRange.length);
		NSRange endingRange = [dataString rangeOfString:@"</url>" options:NSCaseInsensitiveSearch];
		//SHKLog(@"found end string at %d, len %d",endingRange.location,endingRange.length);
		
		if (startingRange.location != NSNotFound && endingRange.location != NSNotFound) {
			NSString *urlString = [dataString substringWithRange:NSMakeRange(startingRange.location + startingRange.length, endingRange.location - (startingRange.location + startingRange.length))];
			//SHKLog(@"extracted string: %@",urlString);
			[item setCustomValue:[NSString stringWithFormat:@"%@ %@",[item customValueForKey:@"status"],urlString] forKey:@"status"];
			[self sendStatus];
		} else {
			[self handleUnsuccessfulTicket:data];
		}
		
		
	} else {
		[self sendDidFailWithError:nil];
	}
}

- (void)sendImageTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error {
	[self sendDidFailWithError:error];
}


- (void)followMe
{
	// remove it so in case of other failures this doesn't get hit again
	[item setCustomValue:nil forKey:@"followMe"];
	
	OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://api.twitter.com/1/friendships/create/%@.json", SHKCONFIG(twitterUsername)]]
																						 consumer:consumer
																							 token:accessToken
																							 realm:nil
																			 signatureProvider:nil];
	
	[oRequest setHTTPMethod:@"POST"];
	
	OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
																													  delegate:nil // Currently not doing any error handling here.  If it fails, it's probably best not to bug the user to follow you again.
																										  didFinishSelector:nil
																											 didFailSelector:nil];	
	
	[fetcher start];
	[oRequest release];
}

#pragma mark -

- (void)handleUnsuccessfulTicket:(NSData *)data
{
	if (SHKDebugShowLogs)
		SHKLog(@"Twitter Send Status Error: %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
	
	// CREDIT: Oliver Drobnik
	
	NSString *string = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];		
	
	// in case our makeshift parsing does not yield an error message
	NSString *errorMessage = @"Unknown Error";		
	
	NSScanner *scanner = [NSScanner scannerWithString:string];
	
	// skip until error message
	[scanner scanUpToString:@"\"error\":\"" intoString:nil];
	
	
	if ([scanner scanString:@"\"error\":\"" intoString:nil])
	{
		// get the message until the closing double quotes
		[scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\""] intoString:&errorMessage];
	}
	
	
	// this is the error message for revoked access ...?... || removed app from Twitter
	if ([errorMessage isEqualToString:@"Invalid / used nonce"] || [errorMessage isEqualToString:@"Could not authenticate with OAuth."]) {
		
		[self shouldReloginWithPendingAction:SHKPendingSend];
		
	} else {
		
		//when sharing image, and the user removed app permissions there is no JSON response expected above, but XML, which we need to parse. 401 is obsolete credentials -> need to relogin
		if ([[SHKXMLResponseParser getValueForElement:@"code" fromResponse:data] isEqualToString:@"401"]) {
			
			[self shouldReloginWithPendingAction:SHKPendingSend];
			return;
		}
	}
	
	NSError *error = [NSError errorWithDomain:@"Twitter" code:2 userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
	[self sendDidFailWithError:error];
}


#pragma mark - alert view delegate
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != alertView.cancelButtonIndex) {
        self.iOS5twitterAccount = [self.iOS5twitterAccountsArray objectAtIndex:buttonIndex - 1];
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:[self.iOS5twitterAccount username], @"screen_name", [[self.iOS5twitterAccount valueForKey:@"properties"] valueForKey:@"user_id"], @"id", nil];
        [[NSUserDefaults standardUserDefaults] setObject:userInfo forKey:kSHKTwitterUserInfo];
        [super authDidFinish:YES];
    }
    else
    {
        iOS5twitterAccountsArray = nil;
        iOS5twitterAccount = nil;
        [super authDidFinish:NO];
    }
}


@end
