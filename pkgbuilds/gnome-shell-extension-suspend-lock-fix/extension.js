import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// ScreenShield._prepareForSleep() locks with animation (lock(true)) before
// suspend. The animation needs compositor frames, but gsd-power blanks the
// panel the moment suspend starts, so the animation stalls, the shield's
// suspend delay-inhibitor is never released in time (logind proceeds at its
// 5s cap), and the deferred _setActive(true) -- which emits
// ActiveChanged(true) -- executes AFTER resume, whereupon gsd-power blanks
// the freshly woken screen. The non-animated lock path calls _setActive(true)
// synchronously, releasing the inhibitor within milliseconds and emitting
// ActiveChanged before the system sleeps.
//
// _prepareForSleep is bound at construction, so we cannot override it; we
// patch the instance's lock() (looked up at call time) to force the
// non-animated path for every caller.

export default class SuspendLockFixExtension extends Extension {
    enable() {
        const shield = Main.screenShield;
        this._origLock = shield.lock;
        const origLock = this._origLock;
        shield.lock = function (_animate) {
            return origLock.call(this, false);
        };
    }

    disable() {
        // session-modes includes "unlock-dialog": the extension stays
        // enabled while the screen is locked (a suspend from the lock
        // screen must also take the patched path), so disable() only
        // runs on real teardown.
        if (this._origLock) {
            Main.screenShield.lock = this._origLock;
            this._origLock = null;
        }
    }
}
