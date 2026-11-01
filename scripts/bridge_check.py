#!/usr/bin/env python3
"""The Bridge Done check. Run it from the repository root after the build:

    python3 scripts/bridge_check.py [out.png]

First it runs bridge-echo, tells two messages on the port echo and checks that
the step reply holds them as Tell Commands, then checks that a tell on a port
that nobody Listens to is dropped. It then points at bridge-echo's tagged
Panels: the button, the menu that floats under it and the scrolling log. It
checks ui.over and ui.scroll in the scene reply, and that a click on the
button comes back as a Tell. Then it turns devices on, injects a real pointer
move and a click over the button, and checks the click Tell. With devices off,
the same click does not reach the game. Keep your mouse off the window during
a local run, because the real pointer moves it.

Then it runs tutorial chapter 3 with ROCCO_BRIDGE, holds W for 30 steps and
checks that Pip's Draw moved by the expected distance. Then it saves a
screenshot, by default into a temporary folder, and checks its size.

Then it runs tutorial chapter 8 and checks the music and the hum in the door's
Group. It holds W until Pip takes a pickup. The step reply must hold the Play
of the blip. Pip then takes the other pickups, and the creak Speaker must join
the door's Group as the door rises. Pip walks through the open door before the
creak ends, and the creak must leave the Scene. A run with no audio device
still returns the Play and the Speakers, so the check needs no sound card.

Then it runs tutorial chapter 9 with the left stick of one pad halfway up,
and checks that Pip walks at half the speed of W. A tap of Start must quit.

Then it runs tutorial chapter 10, checks that Pip stands in Idle and saves
a screenshot next to the first one, with "-still" before the extension. It
holds D until Pip is mid-walk, checks the Pose, saves a "-walk" screenshot
and checks that the two screenshots differ.

Last it runs pong and checks that the `scene` reply holds the UI as a tree:
the scoreboard is a Panel that holds two cell Panels, each with the score. Then
it holds South on a pad, which pauses pong as Space does, and checks that the
UI shows the Paused banner and that the ball stops.

Then it runs widgets. It drags the log's thumb, scrolls with the wheel, clicks
Add and checks that the log sticks to the bottom only until the person scrolls
up. It moves the focus with Tab and Shift-Tab, opens the accordion with Enter,
picks a dropdown item that floats over the header, closes the menu with a press
outside it, and checks that a press on one button and a release on another
click nothing. Last it clicks the icon Button, a Panel that shows a frame of
the sprite sheet, and checks the click Tell and the image in the scene reply.

RUN_PREFIX wraps each game, as in run-games.sh, for example the xvfb-run line
in the Linux image.
"""

import os
import shlex
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bridge

# The protocol of engine/bridge_ops.odin.
PROTOCOL = 9
# examples/bridge-echo/main.roc
ECHO_BUTTON_ID = 7
ECHO_MENU_ID = 8
ECHO_LOG_ID = 9
PIP_ID = 2
STEPS = 30
# examples/tutorial/03-moving/main.roc: speed 2.5 units a second, 120 steps a
# second, W walks along -z.
EXPECTED_DZ = -2.5 * STEPS / 120
TOLERANCE = 1e-4
WINDOW = [960, 540]

# examples/tutorial/08-sound/main.roc: the Speaker ids, the door's Group id,
# and the place of the door's Speakers in the Group. With W held, Pip touches
# pickup 12 in step 27 (guide/bridge.md), so the game collects it in step 28.
MUSIC_SPEAKER_ID = 1
HUM_SPEAKER_ID = 2
CREAK_SPEAKER_ID = 3
DOOR_GROUP_ID = 1
DOOR_SPEAKER_AT = {"At": {"pos": {"x": 0, "y": 0, "z": 0}, "range": 10}}
# Pip walks 2.5 / 120 units a step. After the first STEPS of W, these legs take
# pickups 10, 13 and 14, and stop just short of pickup 11.
PICKUP_ROUTE = [("W", 54), ("A", 96), ("S", 168), ("D", 190), ("W", 144)]
# W then takes pickup 11, and the door starts to rise. A walks Pip to the middle
# of the doorway, and W pushes Pip into the door until it opens.
LAST_PICKUP_STEPS = 12
TO_DOORWAY_STEPS = 94
THROUGH_STEPS = 80
# examples/tutorial/source/make_sounds.py: the creak lasts 4 seconds.
CREAK_STEPS = 4 * 120

# examples/tutorial/09-gamepad/main.roc: the stick's length scales the speed.
HALF_STICK_DZ = EXPECTED_DZ / 2

# examples/tutorial/10-animation/main.roc: the walk time moves by dt x speed
# over the walk speed, and both speeds are 2.5, so it moves 1 s each second. D
# for 70 steps puts Pip mid-stride in the 1 s Walk Clip.
WALK_STEPS = 70
EXPECTED_WALK_TIME = WALK_STEPS / 120
WALK_TOLERANCE = 1e-3
# Pip and the camera move between the still and the walk screenshots, so far
# more pixels than this change.
MIN_CHANGED_PIXELS = 1000

# examples/pong/main.roc: the scoreboard is the first root, a cell, a colon and
# a cell. Each cell is a Panel that holds the score as one Text.
SCOREBOARD_TEXTS = ["0", ":", "0"]

# examples/widgets/main.roc: the ids, the accordion body and the points, in
# logical pixels of the 960 by 540 window. A button is 32 pixels high. The log
# is 108 high and shows six rows of 18. The thumb point is in the thumb while
# the log is at the bottom of 12 rows.
WIDGETS_FILTER_ID = 2
WIDGETS_MENU_ID = 3
WIDGETS_LOG_ID = 5
WIDGETS_ICON_ID = 7
BODY_TEXT = "Tab moves the focus. Enter clicks."
ADD_POINT = (96, 32)
FILTER_POINT = (264, 32)
# The menu's second item, Ready, at y 80 to 112, floats over the header at y 56
# to 88.
ITEM_POINT = (264, 84)
LOG_POINT = (200, 150)
THUMB_POINT = (432, 177)
EMPTY_POINT = (700, 300)
# The icon Button is 48 pixels square, first in the Images row at the top right.
ICON_POINT = (744, 48)


def binary_suffix():
    lines = subprocess.run(["roc", "scripts/build.roc", "--", "target"], check=True, capture_output=True, text=True).stdout
    for line in lines.splitlines():
        if line.startswith("suffix="):
            return line[len("suffix=") :]
    raise RuntimeError("roc scripts/build.roc -- target printed no suffix")


# Pip is a root Node of the tutorial's Scene, so its pos is in the world.
def pip_pos(reply):
    nodes = reply["scene"]["nodes"]
    draws = [n["Draw"] for n in nodes if "Draw" in n and n["Draw"]["id"] == PIP_ID]
    if len(draws) != 1:
        raise AssertionError(f"expected one root Draw with id {PIP_ID}, got {nodes}")
    return draws[0]["pos"]


def check(condition, message):
    if not condition:
        raise AssertionError(message)
    print(f"PASS: {message}")


def drive_echo(b, _out):
    hello = b.hello()
    check(hello["protocol"] == PROTOCOL, f"hello: {hello}")

    tricky = 'a "q"\n\tü'
    b.tell("echo", "")
    b.tell("echo", tricky)
    commands = b.step(1)["commands"]
    want = [{"Tell": {"port": "echo", "msg": ""}}, {"Tell": {"port": "echo", "msg": tricky}}]
    check(commands == want, f"bridge-echo Tells both messages back in order: {commands}")

    b.tell("nobody", "lost")
    commands = b.step(1)["commands"]
    check(commands == [], f"a tell on a port that nobody Listens to is dropped: {commands}")

    commands = b.step(1)["commands"]
    check(commands == [], f"with nothing queued, nothing comes back: {commands}")

    b.step(1, pointer={"x": 884, "y": 36})
    ui = b.scene()["results"]["ui"]
    check(ui["over"] == [ECHO_BUTTON_ID], f"the pointer is over the button: {ui}")
    want_scroll = [{"id": ECHO_LOG_ID, "view": {"width": 200, "height": 100}, "content": {"width": 200, "height": 200}}]
    check(ui["scroll"] == want_scroll, f"the log lists its view and content sizes: {ui}")

    commands = b.step(1, pointer={"x": 884, "y": 36, "tap": ["Left"]})["commands"]
    check(commands == [{"Tell": {"port": "click", "msg": str(ECHO_BUTTON_ID)}}], f"a click on the button Tells click: {commands}")

    b.step(1, pointer={"x": 884, "y": 75})
    over = b.scene()["results"]["ui"]["over"]
    check(over == [ECHO_MENU_ID], f"the menu floats under the button: {over}")

    b.step(1, pointer={"x": 100, "y": 500})
    over = b.scene()["results"]["ui"]["over"]
    check(over == [ECHO_LOG_ID], f"the pointer is over the log: {over}")

    b.step(1)
    over = b.scene()["results"]["ui"]["over"]
    check(over == [], f"with no pointer, nothing is under it: {over}")

    drive_echo_devices(b)
    b.quit()


# inject feeds the real devices, as the window does, so the click goes through
# the merge with no OS input.
def drive_echo_devices(b):
    hello = b.hello(devices=True)
    check(hello["protocol"] == PROTOCOL and hello["devices"] is True, f"hello with devices: {hello}")

    b.inject([{"type": "mouse_move", "x": 884, "y": 36}])
    b.step(1)
    over = b.scene()["results"]["ui"]["over"]
    check(over == [ECHO_BUTTON_ID], f"the real pointer passes through to the button: {over}")

    click = [{"type": "mouse_down", "button": "Left"}, {"type": "mouse_up", "button": "Left"}]
    b.inject(click)
    commands = b.step(1)["commands"]
    check(commands == [{"Tell": {"port": "click", "msg": str(ECHO_BUTTON_ID)}}], f"a real click on the button Tells click: {commands}")

    b.inject(click)
    hello = b.hello()
    check(hello["devices"] is False, f"hello without devices turns them off: {hello}")
    commands = b.step(1)["commands"]
    check(commands == [], f"with devices off, the real click does not reach the game: {commands}")

    try:
        b.inject(click[:1])
    except bridge.BridgeError as err:
        check(str(err) == "inject needs devices on in hello", f"inject with devices off: {err}")
    else:
        check(False, "inject with devices off must fail")


def drive_moving(b, out):
    hello = b.hello()
    check(hello["step_hz"] == 120 and not hello["headless"], f"hello: {hello}")

    before = pip_pos(b.scene())
    stepped = b.step(STEPS, held=["W"])
    check(stepped["steps"] == hello["steps"] + STEPS, f"step ran {STEPS} steps, steps is now {stepped['steps']}")
    after_reply = b.scene()
    check(after_reply["steps"] == stepped["steps"], f"scene is from step {after_reply['steps']}")
    after = pip_pos(after_reply)
    dz = after["z"] - before["z"]
    check(abs(dz - EXPECTED_DZ) < TOLERANCE, f"Pip moved {dz} along z, expected {EXPECTED_DZ}")
    check(after["x"] == before["x"] and after["y"] == before["y"], f"Pip stayed at x {after['x']}, y {after['y']}")

    shot = b.screenshot(out)
    # physical is logical times the display scale: 1 under xvfb, 1 or 2 on a Mac.
    check(shot["logical"] == WINDOW, f"screenshot logical size {shot['logical']}")
    size = bridge.png_size(out)
    check(size == shot["physical"], f"PNG size {size} is the physical size {shot['physical']}")

    b.quit()


def speakers_in(nodes):
    return [node["Speaker"] for node in nodes if "Speaker" in node]


def door_speakers(scene):
    groups = [n["Group"] for n in scene["nodes"] if "Group" in n and n["Group"]["id"] == DOOR_GROUP_ID]
    if len(groups) != 1:
        raise AssertionError(f"expected one Group with id {DOOR_GROUP_ID}, got {scene['nodes']}")
    return speakers_in(groups[0]["children"])


def drive_sound(b, _out):
    b.hello()

    scene = b.scene()["scene"]
    root = speakers_in(scene["nodes"])
    check([s["id"] for s in root] == [MUSIC_SPEAKER_ID], f"the root Speaker is the music: {root}")
    music = root[0]
    check(music["sound"] != 0 and music["at"] == "Here", f"the music plays Here: {music}")
    door = door_speakers(scene)
    check([s["id"] for s in door] == [HUM_SPEAKER_ID], f"the door's Group holds the hum and no creak: {door}")
    hum = door[0]
    check(hum["sound"] != 0 and hum["at"] == DOOR_SPEAKER_AT, f"the hum plays at the centre of the door's Group: {hum}")

    stepped = b.step(STEPS, held=["W"])
    plays = [c["Play"] for c in stepped["commands"] if isinstance(c, dict) and "Play" in c]
    check(len(plays) == 1, f"one Play in {STEPS} steps, commands {stepped['commands']}")
    play = plays[0]
    check(play["sound"] not in (0, music["sound"], hum["sound"]), f"the Play has the blip's Sound id {play['sound']}")
    check(play["gain"] == 1 and play["pitch"] == 1 and play["at"] == "Here", f"the Play is Sound.play: {play}")

    for key, n in PICKUP_ROUTE:
        b.step(n, held=[key])
    shut = b.scene()
    check("Pickups: 4 / 5" in ui_strings(shut["scene"]["ui"]), "Pip took four pickups")
    check([s["id"] for s in door_speakers(shut["scene"])] == [HUM_SPEAKER_ID], "the door is shut, so there is no creak")

    b.step(LAST_PICKUP_STEPS, held=["W"])
    door = door_speakers(b.scene()["scene"])
    check([s["id"] for s in door] == [HUM_SPEAKER_ID, CREAK_SPEAKER_ID], f"the door rises with the hum and the creak in its Group: {door}")
    creak = door[1]
    check(creak["sound"] not in (0, music["sound"], hum["sound"], play["sound"]), f"the creak has its own Sound id {creak['sound']}")
    check(creak["repeat"] == "Once" and creak["at"] == DOOR_SPEAKER_AT, f"the creak plays once at the door: {creak}")

    b.step(TO_DOORWAY_STEPS, held=["A"])
    b.step(THROUGH_STEPS, held=["W"])
    won = b.scene()
    check("You win! Press Escape to quit." in ui_strings(won["scene"]["ui"]), "Pip walked through the open door")
    check(door_speakers(won["scene"]) == [], "the creak left the door's Group, after the hum")
    elapsed = won["steps"] - shut["steps"]
    check(elapsed < CREAK_STEPS, f"Pip walked through less than {elapsed} steps after the creak started, before it ended")

    b.quit()


def drive_gamepad(b, _out):
    b.hello()

    before = pip_pos(b.scene())
    b.step(STEPS, gamepads=[{"slot": 0, "left_stick": [0.0, 0.5]}])
    after_reply = b.scene()
    after = pip_pos(after_reply)
    dz = after["z"] - before["z"]
    check(abs(dz - HALF_STICK_DZ) < TOLERANCE, f"the stick halfway up moved Pip {dz} along z, expected {HALF_STICK_DZ}")
    check(after["x"] == before["x"], f"Pip stayed at x {after['x']}")

    stepped = b.step(10, gamepads=[{"slot": 0, "tap": ["Start"]}])
    check(stepped["commands"] == ["Quit"], f"a tap of Start returns Quit: {stepped['commands']}")
    check(stepped["steps"] == after_reply["steps"] + 1, f"the run stopped at the step that quit, step {stepped['steps']}")


def pip_pose(reply):
    nodes = reply["scene"]["nodes"]
    return [n["Draw"]["pose"] for n in nodes if "Draw" in n and n["Draw"]["id"] == PIP_ID][0]


def drive_animation(b, out):
    b.hello()

    still = pip_pose(b.scene())
    check(still["clip"] != 0 and still["fade_clip"] not in (0, still["clip"]), f"Pip's Pose names Idle and Walk: {still}")
    check(still["fade"] == 0, f"Pip stands in Idle: {still}")
    stem, ext = os.path.splitext(out)
    still_out = f"{stem}-still{ext}"
    b.screenshot(still_out)

    b.step(WALK_STEPS, held=["D"])
    walking = pip_pose(b.scene())
    check(walking["fade"] == 1, f"D held faded all the way to Walk: {walking}")
    walk_time = walking["fade_time"]
    check(abs(walk_time - EXPECTED_WALK_TIME) < WALK_TOLERANCE, f"the walk time is {walk_time}, expected {EXPECTED_WALK_TIME}")

    walk_out = f"{stem}-walk{ext}"
    shot = b.screenshot(walk_out)
    size = bridge.png_size(walk_out)
    check(size == shot["physical"], f"PNG of Pip mid-walk is the physical size {shot['physical']}")
    changed = bridge.png_changed_pixels(still_out, walk_out)
    check(changed > MIN_CHANGED_PIXELS, f"{changed} pixels differ between the still and the walk screenshots")

    b.quit()


def drive_ui(b, _out):
    b.hello()

    ui = b.scene()["scene"]["ui"]
    check(len(ui) > 0 and "Panel" in ui[0], f"the first of {len(ui)} UI roots is a Panel")
    children = ui[0]["Panel"]["children"]
    cells = [c["Panel"] for c in children if "Panel" in c]
    check(len(cells) == 2, f"the scoreboard Panel holds {len(cells)} nested Panels, expected 2")
    texts = [c["Text"]["str"] if "Text" in c else c["Panel"]["children"][0]["Text"]["str"] for c in children]
    check(texts == SCOREBOARD_TEXTS, f"the scoreboard shows {texts}")

    south = [{"slot": 0, "held": ["South"]}]
    b.step(1, gamepads=south)
    paused = b.scene()["scene"]
    check("Paused" in ui_strings(paused["ui"]), "South on a pad pauses pong")
    b.step(10, gamepads=south)
    held = b.scene()
    check(ball_pos(held["scene"]) == ball_pos(paused), "South held for 10 steps does not press again, so the ball stays")

    try:
        b.step(1, gamepads=[{"held": ["Jump"]}])
        check(False, "an unknown GamepadButton fails the step")
    except bridge.BridgeError as err:
        check(str(err) == 'unknown GamepadButton "Jump" in "held"', f"an unknown GamepadButton fails the step: {err}")
    check(b.scene()["steps"] == held["steps"], "the failed step ran no step")

    b.quit()


# The Panel Element with the id in a scene UI tree, or None.
def find_element(elements, panel_id):
    for element in elements:
        if "Panel" not in element:
            continue
        if element["Panel"]["config"]["id"] == panel_id:
            return element
        found = find_element(element["Panel"]["children"], panel_id)
        if found is not None:
            return found
    return None


# The config of the Panel with the id, or None.
def find_panel(elements, panel_id):
    element = find_element(elements, panel_id)
    return None if element is None else element["Panel"]["config"]


def widgets_ui(b):
    return b.scene()["scene"]["ui"]


def log_y(b):
    return find_panel(widgets_ui(b), WIDGETS_LOG_ID)["overflow"]["Scroll"]["y"]


def tells(reply):
    return [c["Tell"]["msg"] for c in reply["commands"] if isinstance(c, dict) and "Tell" in c and c["Tell"]["port"] == "widgets"]


def at(point, **rest):
    return dict({"x": point[0], "y": point[1]}, **rest)


# Each pointer action is a hover step, then an action step, because the game
# sees the Panels under the pointer one step after the pointer moves there.
def tap_at(b, point):
    b.step(1, pointer=at(point))
    return b.step(1, pointer=at(point, tap=["Left"]))


def drive_widgets(b, out):
    b.hello()
    for _ in range(3):
        b.step(1)
    reply = b.scene()
    rows = [r for r in reply["results"]["ui"]["scroll"] if r["id"] == WIDGETS_LOG_ID]
    check(len(rows) == 1 and rows[0]["view"]["height"] == 108 and rows[0]["content"]["height"] == 216, f"the log is 108 high and its 12 rows are 216: {rows}")
    check(find_panel(reply["scene"]["ui"], WIDGETS_LOG_ID)["overflow"]["Scroll"]["y"] == -108, "the log starts stuck to the bottom")

    b.step(1, pointer=at(THUMB_POINT))
    b.step(1, pointer=at(THUMB_POINT, held=["Left"]))
    b.step(1, pointer=at((THUMB_POINT[0], 150), held=["Left"]))
    b.step(1, pointer=at((THUMB_POINT[0], 150)))
    y = log_y(b)
    check(y == -54, f"a drag of the thumb up by 27 pixels scrolls the log up by 54: {y}")

    b.step(1, pointer=at(LOG_POINT))
    b.step(1, pointer=at(LOG_POINT, wheel=[0, -3]))
    y = log_y(b)
    check(y == -108, f"the wheel down by 3 lines scrolls the log to the bottom: {y}")

    said = tells(tap_at(b, ADD_POINT))
    check(said == ["clicked 1"], f"a click on Add Tells it: {said}")
    b.step(1)
    y = log_y(b)
    check(y == -126, f"the stuck log follows the new line one step later: {y}")

    b.step(1, pointer=at(LOG_POINT))
    b.step(1, pointer=at(LOG_POINT, wheel=[0, 1]))
    y = log_y(b)
    check(y == -108, f"the wheel up by one line scrolls the log up by 18: {y}")
    said = tells(tap_at(b, ADD_POINT))
    check(said == ["clicked 1"], f"a second click on Add Tells it: {said}")
    b.step(1)
    y = log_y(b)
    check(y == -108, f"a log that the person scrolled up keeps its offset as a line arrives: {y}")

    for _ in range(4):
        b.step(1, tap=["Tab"])
    b.step(1, tap=["End"])
    y = log_y(b)
    check(y == -144, f"four Tabs focus the log, and End scrolls it to the bottom of 14 rows: {y}")
    b.step(1, held=["LeftShift"], tap=["Tab"])
    said = tells(b.step(1, tap=["Enter"]))
    check(said == ["clicked 4"], f"Shift-Tab focuses the header, and Enter clicks it: {said}")
    check(BODY_TEXT in ui_strings(widgets_ui(b)), "the accordion body shows")

    said = tells(tap_at(b, FILTER_POINT))
    check(said == ["clicked 2"], f"a click on the filter Tells it: {said}")
    check(find_panel(widgets_ui(b), WIDGETS_MENU_ID) is not None, "the click opens the menu")
    stem, ext = os.path.splitext(out)
    b.screenshot(f"{stem}-widgets{ext}")
    said = tells(tap_at(b, ITEM_POINT))
    check(said == ["clicked 11", "selected 1"], f"a click on Ready, over the header, reaches the item only: {said}")
    ui = widgets_ui(b)
    check(find_panel(ui, WIDGETS_MENU_ID) is None, "the pick closes the menu")
    check(BODY_TEXT in ui_strings(ui), "the header got no click, so the body still shows")
    label = ui_strings([find_element(ui, WIDGETS_FILTER_ID)])
    check(label == ["Ready"], f"the filter shows the picked item: {label}")

    said = tells(tap_at(b, FILTER_POINT))
    check(said == ["clicked 2"], f"a click on the filter opens the menu again: {said}")
    said = tells(tap_at(b, EMPTY_POINT))
    check(said == [], f"a press outside the menu Tells nothing: {said}")
    check(find_panel(widgets_ui(b), WIDGETS_MENU_ID) is None, "a press outside the menu closes it")

    replies = [
        b.step(1, pointer=at(ADD_POINT)),
        b.step(1, pointer=at(ADD_POINT, held=["Left"])),
        b.step(1, pointer=at(FILTER_POINT, held=["Left"])),
        b.step(1, pointer=at(FILTER_POINT)),
    ]
    said = [msg for reply in replies for msg in tells(reply)]
    check(said == [], f"a press on Add and a release on the filter click nothing: {said}")

    said = tells(tap_at(b, ICON_POINT))
    check(said == ["clicked 7"], f"a click on the icon Button Tells it: {said}")
    show = find_panel(widgets_ui(b), WIDGETS_ICON_ID)["image"]["Show"]
    frame = {"Px": {"x": 0, "y": 0, "w": 16, "h": 16}}
    check(show["fit"] == "Fit" and show["image"]["region"] == frame and show["image"]["id"] != 0, f"the icon Button shows the first frame of the loaded sheet: {show}")

    b.quit()


def ui_strings(elements):
    strings = []
    for element in elements:
        if "Text" in element:
            strings.append(element["Text"]["str"])
        else:
            strings += ui_strings(element["Panel"]["children"])
    return strings


# The ball's draw id changes with each serve, and it is the last root Draw.
def ball_pos(scene):
    draws = [n["Draw"] for n in scene["nodes"] if "Draw" in n]
    return draws[-1]["pos"]


GAMES = [("bridge-echo", drive_echo), ("tutorial/03-moving", drive_moving), ("tutorial/08-sound", drive_sound), ("tutorial/09-gamepad", drive_gamepad), ("tutorial/10-animation", drive_animation), ("pong", drive_ui), ("widgets", drive_widgets)]


def run_game(game, drive, out, tmp, suffix):
    folder = os.path.join("examples", game)
    name = os.path.basename(game)
    command = shlex.split(os.environ.get("RUN_PREFIX", "")) + [os.path.abspath(os.path.join(folder, name + suffix))]
    port = bridge.free_port()
    env = dict(os.environ, ROCCO_BRIDGE=str(port))
    log_path = os.path.join(tmp, name + ".log")
    print(f"== bridge check: {game} on port {port}")
    with open(log_path, "w") as log:
        process = subprocess.Popen(command, cwd=folder, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            with bridge.Bridge.connect(port, wait=120, process=process) as b:
                drive(b, out)
            code = process.wait(timeout=60)
            check(code == 0, f"the game exited with code {code}")
        except BaseException:
            if process.poll() is None:
                process.kill()
                process.wait()
            log.flush()
            with open(log_path, errors="replace") as f:
                print(f.read()[-4000:], file=sys.stderr)
            raise


def main(argv):
    suffix = binary_suffix()
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.abspath(argv[0]) if argv else os.path.join(tmp, "bridge-check.png")
        for game, drive in GAMES:
            run_game(game, drive, out, tmp, suffix)
    print("PASS: bridge check")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
