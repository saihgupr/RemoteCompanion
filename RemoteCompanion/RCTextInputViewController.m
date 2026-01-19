#import "RCTextInputViewController.h"

@interface RCTextInputViewController () <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@end

@implementation RCTextInputViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = _promptTitle ?: @"Enter Text";
    
    // Add cancel and right bar buttons
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] 
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel 
        target:self 
        action:@selector(cancel)];
    
    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] 
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave 
        target:self 
        action:@selector(save)];
    self.navigationItem.rightBarButtonItem = saveButton;
    
    // Create container for better layout
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:container];
    
    // Add message label if provided
    if (_promptMessage) {
        UILabel *messageLabel = [[UILabel alloc] init];
        messageLabel.text = _promptMessage;
        messageLabel.font = [UIFont systemFontOfSize:14];
        messageLabel.textColor = [UIColor secondaryLabelColor];
        messageLabel.numberOfLines = 0;
        messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:messageLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [messageLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:20],
            [messageLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20],
            [messageLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-20]
        ]];
    }
    
    // Create text view with border
    _textView = [[UITextView alloc] init];
    _textView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    _textView.layer.borderColor = [UIColor separatorColor].CGColor;
    _textView.layer.borderWidth = 1.0;
    _textView.layer.cornerRadius = 8;
    _textView.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
    _textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _textView.autocorrectionType = UITextAutocorrectionTypeNo;
    _textView.keyboardType = UIKeyboardTypeDefault;
    _textView.editable = YES;
    _textView.selectable = YES;
    _textView.delegate = self;
    
    // Create toolbar for keyboard
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 44)];
    UIBarButtonItem *flexSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *kbPasteButton = [[UIBarButtonItem alloc] initWithTitle:@"Paste" style:UIBarButtonItemStylePlain target:self action:@selector(pasteFromClipboard)];
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:_textView action:@selector(resignFirstResponder)];
    [toolbar setItems:@[kbPasteButton, flexSpace, doneButton]];
    
    _textView.inputAccessoryView = toolbar;
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    
    if (_initialText) {
        _textView.text = _initialText;
    }
    
    [container addSubview:_textView];
    
    CGFloat topOffset = _promptMessage ? 60 : 20;
    
    [NSLayoutConstraint activateConstraints:@[
        [container.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [container.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [container.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [container.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        
        [_textView.topAnchor constraintEqualToAnchor:container.topAnchor constant:topOffset],
        [_textView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20],
        [_textView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-20],
        [_textView.heightAnchor constraintGreaterThanOrEqualToConstant:300]
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_textView becomeFirstResponder];
}

- (void)pasteFromClipboard {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSString *clipboardString = pasteboard.string;
    
    if (!clipboardString) {
        // Recovery logic for when .string is nil but data exists
        NSArray *typesToTry = @[@"public.utf8-plain-text", @"public.text", @"com.apple.plain-text"];
        for (NSString *type in typesToTry) {
            NSData *data = [pasteboard dataForPasteboardType:type];
            if (data) {
                NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (str && str.length > 0) {
                    clipboardString = str;
                    break;
                }
            }
        }
    }
    
    if (clipboardString && clipboardString.length > 0) {
        NSRange selectedRange = _textView.selectedRange;
        NSString *currentText = _textView.text ?: @"";
        NSMutableString *newText = [currentText mutableCopy];
        [newText replaceCharactersInRange:selectedRange withString:clipboardString];
        _textView.text = newText;
        _textView.selectedRange = NSMakeRange(selectedRange.location + clipboardString.length, 0);
        
        // Visual Feedback
        _textView.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.1];
        [UIView animateWithDuration:0.3 animations:^{
            _textView.backgroundColor = [UIColor systemBackgroundColor];
        }];
    }
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    NSString *text = [_textView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (_onComplete) {
        _onComplete(text);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
