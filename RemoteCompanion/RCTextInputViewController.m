#import "RCTextInputViewController.h"

@interface RCTextInputViewController () <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@end

@implementation RCTextInputViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.title = _promptTitle ?: @"Editor";
    
    // Add cancel and save buttons
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] 
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel 
        target:self 
        action:@selector(cancel)];
    
    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] 
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave 
        target:self 
        action:@selector(save)];
    self.navigationItem.rightBarButtonItem = saveButton;
    
    // Create text view
    _textView = [[UITextView alloc] init];
    _textView.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
    _textView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    _textView.textContainerInset = UIEdgeInsetsMake(15, 15, 15, 15);
    _textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _textView.autocorrectionType = UITextAutocorrectionTypeNo;
    _textView.keyboardType = UIKeyboardTypeDefault;
    _textView.editable = YES;
    _textView.selectable = YES;
    _textView.delegate = self;
    _textView.alwaysBounceVertical = YES;
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_textView];
    
    // Simple toolbar with just Done
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 44)];
    UIBarButtonItem *flexSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:_textView action:@selector(resignFirstResponder)];
    [toolbar setItems:@[flexSpace, doneButton]];
    _textView.inputAccessoryView = toolbar;
    
    if (_initialText) {
        _textView.text = _initialText;
    }
    
    [NSLayoutConstraint activateConstraints:@[
        [_textView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_textView becomeFirstResponder];
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
