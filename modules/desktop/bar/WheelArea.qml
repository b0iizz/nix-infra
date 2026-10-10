// A MouseArea whose wheel comes in steps: one per notch of a mouse wheel
// (120 units of angleDelta), and as many for a touchpad as its swipe adds up
// to, instead of one for each of the many small events a touchpad sends.
// The bar items that scroll a value (Brightness, Volume) use it.
import QtQuick

MouseArea {
    id: area

    property real pending: 0

    // positive up, negative down
    signal stepped(int steps)

    onWheel: w => {
        pending += w.angleDelta.y;
        const steps = Math.trunc(pending / 120);
        if (steps !== 0) {
            pending -= steps * 120;
            area.stepped(steps);
        }
    }
}
