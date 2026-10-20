r"""Maidshare window: one place to send to a phone and one to receive.

The window wraps the same `maidshare` CLI the right-click menu uses -
nothing here starts a new daemon or invents a second backend. Send
keeps a list of files and links and runs the CLI once per send; the
backend order (kdeconnect, adb, then the throwaway QR http link) is
the CLI's own auto-pick. Receive starts the temporary https server,
then shows what the CLI prints as the things you actually need: the
QR, the token URL and the cert fingerprint to compare with the
browser's certificate warning. Stopping the listen - or closing the
window - stops the server.

The look follows the Maid Scroll palette state, the same six palettes
the rest of the suite reads from ~/.config/maid-scroll/.

--screenshot renders the window without a display (offscreen) and
writes a PNG for docs. Its sample rows are demo text only.
"""

import os
import re
import shutil
import signal
import subprocess
import sys

from PyQt6.QtCore import QProcess, Qt
from PyQt6.QtGui import QColor, QFontDatabase, QPalette, QPixmap
from PyQt6.QtWidgets import (QApplication, QComboBox, QFileDialog,
                             QHBoxLayout, QInputDialog, QLabel,
                             QListWidget, QListWidgetItem, QMainWindow,
                             QPlainTextEdit, QPushButton, QSpinBox,
                             QTabWidget, QVBoxLayout, QWidget)

from .palettes import PALETTES, load

# Where the window looks for the CLI: MAIDSHARE_BIN wins, then the
# install layout (lib/maidshare-gui sits next to bin/), then a repo
# checkout, then PATH.
CLI_NAME = "maidshare"
DEFAULT_MINUTES = 10
MIN_MINUTES = 1
MAX_MINUTES = 120

BACKENDS = [
    ("auto", "auto - kdeconnect, adb, then QR"),
    ("kdeconnect", "kdeconnect (paired phone on the lan)"),
    ("adb", "adb push to the phone's download folder"),
    ("http", "qr link, no phone setup"),
]

URL_LINE = re.compile(r"^MaidShare receive at (\S+) -> (\S+) \((\d+) min", re.M)
FP_LINE = re.compile(r"^cert fingerprint \(compare with the browser warning\): (\S+)", re.M)
OUTDIR_LABEL = "files land in ~/Downloads/MaidShare"


def find_cli():
    override = os.environ.get("MAIDSHARE_BIN")
    if override:
        return override
    here = os.path.dirname(os.path.realpath(__file__))
    # repo checkout: src/maidshare_gui -> pkg root; installed:
    # .local/lib/maidshare-gui -> .local
    for up in range(1, 5):
        base = here
        for _ in range(up):
            base = os.path.dirname(base)
        cand = os.path.join(base, "bin", CLI_NAME)
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    found = shutil.which(CLI_NAME)
    return found or CLI_NAME


def send_args(cli, files, via="auto"):
    """The argv the send run uses. Pure, so the suite can check it."""
    args = [cli]
    if via and via != "auto":
        args += ["--via", via]
    args.extend(files)
    return args


def parse_receive_output(text):
    """Pull (url, outdir, minutes, fingerprint) out of CLI stdout."""
    url = outdir = fp = None
    minutes = None
    m = URL_LINE.search(text)
    if m:
        url, outdir, minutes = m.group(1), m.group(2), int(m.group(3))
    m = FP_LINE.search(text)
    if m:
        fp = m.group(1)
    return url, outdir, minutes, fp


def make_qr_png(url, out_path):
    """Render the QR as a PNG file; None clicks when qrencode is absent."""
    if not shutil.which("qrencode"):
        return False
    try:
        done = subprocess.run(
            ["qrencode", "-t", "PNG", "-s", "8", "-o", out_path, "--", url],
            capture_output=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return False
    return done.returncode == 0 and os.path.isfile(out_path)


def apply_palette(app, name):
    color = next(p for n, p in PALETTES if n == name)
    pal = QPalette()
    pal.setColor(QPalette.ColorRole.Window, QColor(color["bg"]))
    pal.setColor(QPalette.ColorRole.Base, QColor(color["bg_alt"]))
    pal.setColor(QPalette.ColorRole.AlternateBase, QColor(color["bg"]))
    pal.setColor(QPalette.ColorRole.Text, QColor(color["fg"]))
    pal.setColor(QPalette.ColorRole.WindowText, QColor(color["fg"]))
    pal.setColor(QPalette.ColorRole.Button, QColor(color["bg_alt"]))
    pal.setColor(QPalette.ColorRole.ButtonText, QColor(color["fg"]))
    pal.setColor(QPalette.ColorRole.ToolTipBase, QColor(color["bg_alt"]))
    pal.setColor(QPalette.ColorRole.ToolTipText, QColor(color["fg"]))
    pal.setColor(QPalette.ColorRole.Highlight, QColor(color["accent"]))
    pal.setColor(QPalette.ColorRole.HighlightedText,
                 QColor(color["bg"]))
    pal.setColor(QPalette.ColorRole.PlaceholderText,
                 QColor(color["muted"]))
    for group in (QPalette.ColorGroup.Disabled,):
        pal.setColor(group, QPalette.ColorRole.WindowText,
                     QColor(color["muted"]))
        pal.setColor(group, QPalette.ColorRole.Text, QColor(color["muted"]))
        pal.setColor(group, QPalette.ColorRole.ButtonText,
                     QColor(color["muted"]))
    app.setPalette(pal)
    app.setStyle("Fusion")


class MainWindow(QMainWindow):
    def __init__(self, cli, screenshot=False):
        super().__init__()
        self.cli = cli
        self.screenshot = screenshot
        self.send_proc = None
        self.recv_proc = None
        self.recv_url = None
        self.recv_fp = None

        self.setWindowTitle("MaidShare")
        self.resize(600, 560)
        self.statusBar().showMessage("ready - send uses the same CLI as the "
                                     "right-click menu")

        tabs = QTabWidget()
        tabs.addTab(self.build_send_tab(), "send")
        tabs.addTab(self.build_receive_tab(), "receive")
        self.setCentralWidget(tabs)

    # ---- send tab -----------------------------------------------------

    def build_send_tab(self):
        page = QWidget()
        lay = QVBoxLayout(page)
        lay.setContentsMargins(14, 14, 14, 14)
        lay.setSpacing(8)

        intro = QLabel("drag files in, or add them below. links send "
                       "through kdeconnect too.")
        intro.setWordWrap(True)
        lay.addWidget(intro)

        self.file_list = QListWidget()
        self.file_list.setSelectionMode(QListWidget.SelectionMode.ExtendedSelection)
        self.file_list.setAcceptDrops(True)
        self.file_list.setDragDropMode(
            QListWidget.DragDropMode.DropOnly)
        self.file_list.setAlternatingRowColors(True)
        self.file_list.installEventFilter(self)
        lay.addWidget(self.file_list, 1)

        row = QHBoxLayout()
        b_files = QPushButton("add files…")
        b_link = QPushButton("add link…")
        b_del = QPushButton("remove selected")
        b_clear = QPushButton("clear")
        for b in (b_files, b_link, b_del, b_clear):
            row.addWidget(b)
        row.addStretch(1)
        lay.addLayout(row)
        b_files.clicked.connect(self.add_files)
        b_link.clicked.connect(self.add_link)
        b_del.clicked.connect(self.remove_selected)
        b_clear.clicked.connect(self.file_list.clear)

        brow = QHBoxLayout()
        brow.addWidget(QLabel("backend:"))
        self.backend = QComboBox()
        for key, text in BACKENDS:
            self.backend.addItem(text, key)
        brow.addWidget(self.backend, 1)
        lay.addLayout(brow)

        self.send_btn = QPushButton("send to phone")
        self.send_btn.setDefault(True)
        lay.addWidget(self.send_btn)

        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        f = QFontDatabase.systemFont(QFontDatabase.SystemFont.FixedFont)
        f.setPointSize(max(8, f.pointSize() - 1))
        self.log.setFont(f)
        self.log.setMaximumBlockCount(400)
        self.log.setPlaceholderText("the CLI's output lands here "
                                    "(--check style notes too)")
        lay.addWidget(self.log, 1)

        self.send_btn.clicked.connect(self.start_send)
        return page

    def add_files(self):
        paths, _filter = QFileDialog.getOpenFileNames(self, "add files",
                                                      os.path.expanduser("~"))
        for p in paths:
            self.file_list.addItem(QListWidgetItem(p))

    def add_link(self):
        text, ok = QInputDialog.getText(self, "add link",
                                        "http or https URL:")
        if ok and text.strip():
            self.file_list.addItem(QListWidgetItem(text.strip()))

    def remove_selected(self):
        for item in self.file_list.selectedItems():
            self.file_list.takeItem(self.file_list.row(item))

    def selected_items(self):
        return [self.file_list.item(i).text()
                for i in range(self.file_list.count())]

    def eventFilter(self, obj, event):
        if obj is self.file_list:
            ev_type = event.type()
            if ev_type == event.Type.DragEnter and event.mimeData().hasUrls():
                event.acceptProposedAction()
                return True
            if ev_type == event.Type.Drop and event.mimeData().hasUrls():
                for url in event.mimeData().urls():
                    if url.scheme() in ("http", "https"):
                        text = url.toString()
                    elif url.isLocalFile():
                        text = url.toLocalFile()
                    else:
                        continue
                    self.file_list.addItem(QListWidgetItem(text))
                event.acceptProposedAction()
                return True
        return super().eventFilter(obj, event)

    def start_send(self):
        if self.send_proc and self.send_proc.state() != QProcess.ProcessState.NotRunning:
            return
        files = self.selected_items()
        if not files:
            self.statusBar().showMessage("nothing to send - add files "
                                         "or a link first")
            return
        via = self.backend.currentData()
        self.send_proc = QProcess(self)
        self.send_proc.setProgram(self.cli)
        self.send_proc.setArguments(send_args(self.cli, files, via)[1:])
        self.send_proc.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self.send_proc.readyReadStandardOutput.connect(self.read_send_log)
        self.send_proc.finished.connect(self.send_finished)
        self.log.clear()
        self.send_btn.setEnabled(False)
        self.statusBar().showMessage("sending…")
        self.send_proc.start()

    def read_send_log(self):
        data = bytes(self.send_proc.readAllStandardOutput())
        for line in data.decode("utf-8", errors="replace").splitlines():
            self.log.appendPlainText(line.rstrip())

    def send_finished(self, code, _status):
        self.send_btn.setEnabled(True)
        if code == 0:
            self.statusBar().showMessage("done - the phone has the files",
                                         8000)
            self.log.appendPlainText("done (exit 0)")
        else:
            self.statusBar().showMessage(f"failed (exit {code}) - see the "
                                         "log below", 8000)

    # ---- receive tab --------------------------------------------------

    def build_receive_tab(self):
        page = QWidget()
        lay = QVBoxLayout(page)
        lay.setContentsMargins(14, 14, 14, 14)
        lay.setSpacing(8)

        intro = QLabel("start the listen, scan the QR with the phone's "
                       "camera, upload in the browser. the link dies "
                       f"after the minutes run out.")
        intro.setWordWrap(True)
        lay.addWidget(intro)

        row = QHBoxLayout()
        row.addWidget(QLabel("listen for:"))
        self.minutes = QSpinBox()
        self.minutes.setRange(MIN_MINUTES, MAX_MINUTES)
        self.minutes.setValue(DEFAULT_MINUTES)
        self.minutes.setSuffix(" min")
        row.addWidget(self.minutes)
        self.recv_btn = QPushButton("listen")
        row.addWidget(self.recv_btn)
        row.addStretch(1)
        lay.addLayout(row)

        self.qr = QLabel()
        self.qr.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.qr.setMinimumHeight(180)
        lay.addWidget(self.qr, 1)

        self.url_label = QLabel("scan first - if the QR does not work, "
                               "type this on the phone:")
        self.url_label.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
            | Qt.TextInteractionFlag.TextSelectableByKeyboard)
        self.url_label.setWordWrap(True)
        lay.addWidget(self.url_label)

        copy_row = QHBoxLayout()
        self.copy_btn = QPushButton("copy link")
        self.copy_btn.clicked.connect(self.copy_url)
        self.copy_btn.setEnabled(False)
        copy_row.addWidget(self.copy_btn)
        copy_row.addStretch(1)
        lay.addLayout(copy_row)

        fp_title = QLabel("cert fingerprint (compare with the browser "
                         "warning):")
        lay.addWidget(fp_title)
        self.fp_label = QLabel("-")
        self.fp_label.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse)
        lay.addWidget(self.fp_label)

        self.outdir_label = QLabel(OUTDIR_LABEL)
        self.outdir_label.setWordWrap(True)
        lay.addWidget(self.outdir_label)

        self.recv_btn.clicked.connect(self.toggle_receive)
        return page

    def toggle_receive(self):
        if self.recv_proc and self.recv_proc.state() != QProcess.ProcessState.NotRunning:
            self.stop_receive("stopped")
            return
        mins = self.minutes.value()
        self.recv_proc = QProcess(self)
        self.recv_proc.setProgram(self.cli)
        self.recv_proc.setArguments(["--receive", "--time", str(mins)])
        self.recv_proc.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self.recv_proc.readyReadStandardOutput.connect(self.read_recv)
        self.recv_proc.finished.connect(self.recv_finished)
        self.minutes.setEnabled(False)
        self.recv_btn.setText("stop")
        self.statusBar().showMessage(f"listening for {mins} min "
                                     "(stop here or the button)")
        self.recv_proc.start()

    def read_recv(self):
        data = bytes(self.recv_proc.readAllStandardOutput())
        text = data.decode("utf-8", errors="replace")
        url, outdir, _mins, fp = parse_receive_output(text)
        if url and url != self.recv_url:
            self.recv_url = url
            self.url_label.setText(url)
            self.copy_btn.setEnabled(True)
            self.show_qr(url)
        if fp and fp != self.recv_fp:
            self.recv_fp = fp
            self.fp_label.setText(fp)
        if outdir:
            self.outdir_label.setText(OUTDIR_LABEL.replace("~/Downloads/MaidShare",
                                                           outdir.replace(
                                                               os.path.expanduser("~"),
                                                               "~", 1)))
        first = next((l.rstrip() for l in text.splitlines() if l.strip()), "")
        if first and not first.startswith("\u2588"):
            self.statusBar().showMessage(first[:120])

    def show_qr(self, url):
        tmp = os.path.join("/tmp", "maidshare-gui-qr-%d.png" % os.getpid())
        if make_qr_png(url, tmp):
            pix = QPixmap(tmp)
            self.qr.setPixmap(pix.scaled(
                220, 220, Qt.AspectRatioMode.KeepAspectRatio,
                Qt.TransformationMode.FastTransformation))
            os.unlink(tmp)
        else:
            self.qr.setText("(qrencode missing - type the URL instead)")

    def copy_url(self):
        if self.recv_url:
            QApplication.clipboard().setText(
                self.recv_url, QClipboard.Mode.Clipboard)
            self.statusBar().showMessage("link copied", 5000)

    def stop_receive(self, note):
        proc = self.recv_proc
        if not proc or proc.state() == QProcess.ProcessState.NotRunning:
            return
        stop_process(proc)
        self.statusBar().showMessage(note + " - server down, files (if "
                                     "any) already saved")

    def recv_finished(self, code, _status):
        self.recv_btn.setText("listen")
        self.minutes.setEnabled(True)
        if code == 0:
            self.statusBar().showMessage("listen over - files (if any) "
                                         "are in the folder below", 8000)
        else:
            self.statusBar().showMessage(f"receive server stopped "
                                         f"(exit {code})", 8000)

    def closeEvent(self, event):
        for proc in (self.send_proc, self.recv_proc):
            if proc and proc.state() != QProcess.ProcessState.NotRunning:
                stop_process(proc)
        super().closeEvent(event)


def stop_process(proc):
    """Stop a bash-driven CLI: children first, then the shell itself."""
    pid = proc.processId()
    if pid <= 0:
        proc.kill()
        proc.waitForFinished(1000)
        return
    try:
        found = subprocess.run(["pgrep", "-P", str(pid)],
                               capture_output=True, text=True, timeout=5)
        for line in found.stdout.split():
            try:
                os.kill(int(line), signal.SIGTERM)
            except (ValueError, ProcessLookupError, PermissionError):
                pass
    except (OSError, subprocess.SubprocessError):
        pass
    proc.terminate()
    if not proc.waitForFinished(2000):
        try:
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        proc.kill()
    proc.waitForFinished(1000)


def build_window(cli=None, screenshot=False):
    if cli is None:
        cli = find_cli()
    win = MainWindow(cli, screenshot=screenshot)
    inst = QApplication.instance()
    if inst is not None:
        apply_palette(inst, load())
    return win


def demo_rows(win):
    """Sample content for --screenshot; demo paths/URLs only."""
    for text in ("~/Pictures/trip.jpg", "~/Documents/report.pdf",
                 "https://example.org/notes.pdf", "~/Music/demo.mp3"):
        win.file_list.addItem(QListWidgetItem(text))
    win.url_label.setText("https://192.0.2.7:8078/Xk3fQ8-Twqv9NxSLYj2A2w")
    win.url_label.setEnabled(True)
    win.copy_btn.setEnabled(False)
    win.fp_label.setText("(appears while the server runs)")
    win.qr.setPixmap(QPixmap())
    win.qr.setText("the QR appears here while the listen runs")
    win.statusBar().showMessage("ready - send uses the same CLI as the "
                                "right-click menu")


def main(argv=None):
    argv = list(sys.argv if argv is None else argv)
    shot_path = None
    if "--screenshot" in argv:
        i = argv.index("--screenshot")
        try:
            shot_path = argv[i + 1]
        except IndexError:
            shot_path = None
        if shot_path and not shot_path.startswith("-"):
            del argv[i + 1]
        else:
            shot_path = None
        del argv[i]
        shot_path = shot_path or "maidshare-window.png"
        if not os.environ.get("QT_QPA_PLATFORM"):
            os.environ["QT_QPA_PLATFORM"] = "offscreen"
    if "--version" in argv:
        print("MaidShare GUI - wraps the maidshare CLI "
              "(bin/maidshare), no extra machinery")
        return 0
    app = QApplication(argv)
    win = build_window(screenshot=bool(shot_path))
    if shot_path:
        demo_rows(win)
        win.resize(640, 580)
        win.show()
        app.processEvents()
        if win.grab().save(shot_path):
            return 0
        print("MaidShare GUI: screenshot save failed", file=sys.stderr)
        return 1
    win.show()
    return app.exec()
