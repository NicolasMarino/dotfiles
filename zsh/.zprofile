# Login-shell environment. Homebrew and ~/.local/bin are set up in .zshrc so
# that non-login interactive shells get them too; only toolchains that no
# interactive-shell config needs live here.

# Android development: guarded so a machine without the JDK or SDK does not
# get dead PATH entries.
if [ -d "/opt/homebrew/opt/openjdk@17" ]; then
    export JAVA_HOME="/opt/homebrew/opt/openjdk@17"
    export PATH="$JAVA_HOME/bin:$PATH"
fi

if [ -d "$HOME/Library/Android/sdk" ]; then
    export ANDROID_HOME="$HOME/Library/Android/sdk"
    export PATH="$PATH:$ANDROID_HOME/platform-tools"
    export PATH="$PATH:$ANDROID_HOME/emulator"
    export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin"
fi
