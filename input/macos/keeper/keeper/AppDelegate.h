#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

#define SAMPLE_INTERVAL 2   // get active application every 2 seconds
#define AGGREGATE 300       // send data every 300 seconds 

#define UID_LEN 128 // SecureRandom.hex(64) -> gives a string with len 128 http://www.ruby-doc.org/stdlib-1.9.3/libdoc/securerandom/rdoc/SecureRandom.html#method-c-hex

#define URL_REMOTE @"https://keeper.sofialondonmoskva.com"
#define URL_REMOTE_GENERATE_UID URL_REMOTE "/generate/uid/"
#define START_AT_LOGIN_TEXT @"Start at login"
#define DO_NOT_START_AT_LOGIN_TEXT @"Do not start at login"
#define PAUSE_TEXT @"Pause"
#define START_TEXT @"Start"
#define SCRIPT_GET_CURRENT_TAB @"tell application \"Safari\"\n\tset theURL to URL of current tab of window 1\nend tell"


@interface AppDelegate : NSObject <NSApplicationDelegate> {
    NSStatusItem *status_item;
    NSDictionary *scripts;
    NSMutableDictionary *queue;
    NSLock *GIANT;
    NSString *uid;
}
@property (retain) NSMutableDictionary *queue;
@property (retain) NSString *uid;
@property (retain) NSLock *GIANT;
@property (retain) NSDictionary *scripts;
@property (retain) NSStatusItem *status_item;
@end

