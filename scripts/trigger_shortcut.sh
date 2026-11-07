#!/bin/bash
# AliveLock - Kısayol Tetikleyici (Command + 7)
# Yerel Cocoa uygulamasını anında öne getirir

if [ -d "$HOME/Applications/AliveLock.app" ]; then
    open -a "$HOME/Applications/AliveLock.app"
elif [ -d "/Applications/AliveLock.app" ]; then
    open -a "/Applications/AliveLock.app"
else
    open -b "com.alivelock.app" 2>/dev/null || open -a "AliveLock"
fi
