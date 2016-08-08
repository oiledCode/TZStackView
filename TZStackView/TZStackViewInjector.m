//
//  TZStackViewInjector.m
//
//  Created by André Braga on 04/08/16.
//
//

#import <objc/runtime.h>

#import <Foundation/Foundation.h>

// ----------------------------------------------------
// Runtime injection start.
// Assemble codes below are based on:
// https://github.com/0xced/NSUUID/blob/master/NSUUID.m
// ----------------------------------------------------

#pragma mark - Runtime Injection

#define TARGET_CLASS_NAME "TZStackView"
#define DESTINATION_CLASS_NAME "UIStackView"

__asm(
      ".section        __DATA,__objc_classrefs,regular,no_dead_strip\n"
#if	TARGET_RT_64_BIT
      ".align          3\n"
      "L_OBJC_CLASS_"DESTINATION_CLASS_NAME":\n"
      ".quad           _OBJC_CLASS_$_"DESTINATION_CLASS_NAME"\n"
#else
      ".align          2\n"
      "_OBJC_CLASS_"DESTINATION_CLASS_NAME":\n"
      ".long           _OBJC_CLASS_$_"DESTINATION_CLASS_NAME"\n"
#endif
      ".weak_reference _OBJC_CLASS_$_"DESTINATION_CLASS_NAME"\n"
);

static inline bool hasSuffix(const char *str, const char *suffix) {
    if (str == suffix) {
        return true;
    }

    if (!str || !suffix) {
        return false;
    }

    size_t lenStr = strlen(str);
    size_t lenSuffix = strlen(suffix);

    if (lenSuffix > lenStr) {
        return false;
    }

    return strncmp(str + lenStr - lenSuffix, suffix, lenSuffix) == 0;
}

// Constructors are called after all classes have been loaded.
__attribute__((constructor)) static void StackViewPatchEntry(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        @autoreleasepool {
            if (objc_getClass(DESTINATION_CLASS_NAME)) {
                return;
            }

            Class *destinationClassLocation = NULL;

#if TARGET_CPU_ARM
            __asm("movw %0, :lower16:(_OBJC_CLASS_"DESTINATION_CLASS_NAME"-(LPC0+4))\n"
                  "movt %0, :upper16:(_OBJC_CLASS_"DESTINATION_CLASS_NAME"-(LPC0+4))\n"
                  "LPC0: add %0, pc" : "=r"(destinationClassLocation));
#elif TARGET_CPU_ARM64
            __asm("adrp %0, L_OBJC_CLASS_"DESTINATION_CLASS_NAME"@PAGE\n"
                  "add  %0, %0, L_OBJC_CLASS_"DESTINATION_CLASS_NAME"@PAGEOFF" : "=r"(destinationClassLocation));
#elif TARGET_CPU_X86_64
            __asm("leaq L_OBJC_CLASS_"DESTINATION_CLASS_NAME"(%%rip), %0" : "=r"(destinationClassLocation));
#elif TARGET_CPU_X86
            void *pc = NULL;
            __asm("calll L0\n"
                  "L0: popl %0\n"
                  "leal _OBJC_CLASS_"DESTINATION_CLASS_NAME"-L0(%0), %1" : "=r"(pc), "=r"(destinationClassLocation));
#else
#error Unsupported CPU
#endif

            Class injected = NULL;
            int numClasses = objc_getClassList(NULL, 0);
            Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * numClasses);
            objc_getClassList(classes, numClasses);

            // Needs to iterate classes in order to support modules
            // Checks for full name match or suffix after a separating "."
            for (int i = 0; i < numClasses; i++) {
                char *className = class_getName(classes[i]);

                if (hasSuffix(className, TARGET_CLASS_NAME)
                    && (strncmp(className, TARGET_CLASS_NAME, strlen(className)) == 0
                        || hasSuffix(className, "."TARGET_CLASS_NAME))) {
                    injected = classes[i];
                    break;
                }
            }
            free(classes);

            if (injected && destinationClassLocation && !*destinationClassLocation) {
                Class class = objc_allocateClassPair(injected, DESTINATION_CLASS_NAME, 0);
                if (class) {
                    objc_registerClassPair(class);
                    *destinationClassLocation = class;
                    [NSKeyedUnarchiver setClass:class forClassName:@DESTINATION_CLASS_NAME];
                }
            }
        }
    });
}


#ifdef DEBUG

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@implementation UIView (FixViewDebugging_iOS8Simulator)

+ (void)load
{
    Method original = class_getInstanceMethod(self, @selector(viewForBaselineLayout));
    class_addMethod(self, @selector(viewForFirstBaselineLayout), method_getImplementation(original), method_getTypeEncoding(original));
    class_addMethod(self, @selector(viewForLastBaselineLayout), method_getImplementation(original), method_getTypeEncoding(original));
}

@end

#endif
