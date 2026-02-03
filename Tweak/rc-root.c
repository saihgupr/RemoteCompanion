/*
 * rc-root - Setuid root helper for RemoteCommand
 * Executes shell commands as root when called from mobile user
 *
 * Must be installed with: chown root:wheel rc-root && chmod 4755 rc-root
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <spawn.h>
#include <sys/wait.h>
#include <CoreFoundation/CoreFoundation.h>

extern char **environ;

// Read custom paths from preferences plist
char *get_custom_paths(void) {
    const char *prefs_path = "/var/jb/var/mobile/Library/Preferences/com.saihgupr.remotecompanion.plist";

    CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault,
        (const UInt8 *)prefs_path, strlen(prefs_path), false);
    if (!url) return NULL;

    CFReadStreamRef stream = CFReadStreamCreateWithFile(kCFAllocatorDefault, url);
    CFRelease(url);
    if (!stream) return NULL;

    if (!CFReadStreamOpen(stream)) {
        CFRelease(stream);
        return NULL;
    }

    CFPropertyListRef plist = CFPropertyListCreateWithStream(kCFAllocatorDefault,
        stream, 0, kCFPropertyListImmutable, NULL, NULL);
    CFReadStreamClose(stream);
    CFRelease(stream);

    if (!plist) return NULL;

    if (CFGetTypeID(plist) != CFDictionaryGetTypeID()) {
        CFRelease(plist);
        return NULL;
    }

    CFStringRef key = CFStringCreateWithCString(kCFAllocatorDefault, "customPaths", kCFStringEncodingUTF8);
    CFStringRef value = CFDictionaryGetValue((CFDictionaryRef)plist, key);
    CFRelease(key);

    char *result = NULL;
    if (value && CFGetTypeID(value) == CFStringGetTypeID()) {
        CFIndex length = CFStringGetLength(value);
        CFIndex maxSize = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1;
        result = malloc(maxSize);
        if (result) {
            if (!CFStringGetCString(value, result, maxSize, kCFStringEncodingUTF8)) {
                free(result);
                result = NULL;
            }
        }
    }

    CFRelease(plist);
    return result;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: rc-root <command> [args...]\n");
        return 1;
    }

    // Ensure we're running as root (setuid should handle this)
    if (setuid(0) != 0) {
        fprintf(stderr, "Error: Failed to setuid to root\n");
        return 1;
    }

    if (setgid(0) != 0) {
        fprintf(stderr, "Error: Failed to setgid to root\n");
        return 1;
    }

    // Build command string from all arguments for shell execution
    size_t total_len = 0;
    for (int i = 1; i < argc; i++) {
        total_len += strlen(argv[i]) + 1;
    }

    char *cmd = malloc(total_len + 1);
    if (!cmd) {
        fprintf(stderr, "Error: Memory allocation failed\n");
        return 1;
    }

    cmd[0] = '\0';
    for (int i = 1; i < argc; i++) {
        strcat(cmd, argv[i]);
        if (i < argc - 1) {
            strcat(cmd, " ");
        }
    }

    // Use posix_spawn to run sh -c "command"
    // Try rootless path first, fall back to standard path
    pid_t pid;
    const char *shell_path = "/var/jb/usr/bin/sh";

    // Check if rootless shell exists, otherwise use standard path
    if (access(shell_path, X_OK) != 0) {
        shell_path = "/bin/sh";
    }

    // Build PATH with custom paths prepended
    const char *base_path = "/var/jb/usr/local/bin:/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
    char *custom_paths = get_custom_paths();

    char *path_env;
    if (custom_paths && strlen(custom_paths) > 0) {
        // Prepend custom paths
        size_t path_len = strlen("PATH=") + strlen(custom_paths) + 1 + strlen(base_path) + 1;
        path_env = malloc(path_len);
        if (path_env) {
            snprintf(path_env, path_len, "PATH=%s:%s", custom_paths, base_path);
        } else {
            path_env = strdup("PATH=/var/jb/usr/local/bin:/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin");
        }
        free(custom_paths);
    } else {
        path_env = strdup("PATH=/var/jb/usr/local/bin:/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin");
        if (custom_paths) free(custom_paths);
    }

    // Set up environment
    char *new_env[] = {
        path_env,
        "HOME=/var/root",
        NULL
    };

    char *shell_args[] = {(char *)shell_path, "-c", cmd, NULL};

    int status = posix_spawn(&pid, shell_path, NULL, NULL, shell_args, new_env);

    if (status != 0) {
        fprintf(stderr, "Error: posix_spawn failed with status %d\n", status);
        free(cmd);
        free(path_env);
        return 1;
    }

    // Wait for child process
    int exit_status;
    waitpid(pid, &exit_status, 0);

    free(cmd);
    free(path_env);

    if (WIFEXITED(exit_status)) {
        return WEXITSTATUS(exit_status);
    }

    return 1;
}
