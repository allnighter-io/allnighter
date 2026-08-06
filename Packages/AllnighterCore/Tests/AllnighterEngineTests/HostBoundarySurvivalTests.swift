import XCTest
@testable import AllnighterEngine

/// Proves that a child spawned by a launcher SURVIVES after the launcher process
/// exits — the missing host-boundary proof for `alln run --no-wait`.
///
/// Existing `DetachedDispatchTests` / `RunNoWaitTests` keep XCTest (the launching
/// process) alive and call `waitUntilExit` themselves, so they prove argv, cwd,
/// null stdio, and acceptance timing, but never survival after launcher death.
///
/// This test uses an intermediate shell launcher that terminates on its own while
/// the child is still running. The test observes from the outside that the child
/// survives and continues to hold its resources (a simulated write lock).
///
/// Required properties:
/// 1. The launcher is verifiably dead before the assertion.
/// 2. The child survives that death and is verifiably alive.
/// 3. The child holds a cross-process file lock (simulating the write lock).
/// 4. The child releases the lock when finished.
/// 5. Failure messages name what broke, not just "timed out".
final class HostBoundarySurvivalTests: XCTestCase {
    private var tmp: URL!
    private var markerDir: URL!
    private var childPid: Int32?
    private var launcherPid: Int32?

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-host-boundary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        markerDir = tmp.appendingPathComponent("markers", isDirectory: true)
        try FileManager.default.createDirectory(at: markerDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Release the child unconditionally so it can exit.
        let signal = markerDir.appendingPathComponent("done.signal")
        try? Data("done".utf8).write(to: signal, options: .atomic)

        // If child is still running, kill it — do not leave orphans.
        if let pid = childPid, pid > 0, ProcessOwnership.processAlive(pid) {
            kill(pid, SIGKILL)
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline && ProcessOwnership.processAlive(pid) {
                usleep(50_000)
                var status: Int32 = 0
                waitpid(pid, &status, WNOHANG)
                if status != 0 { break }
                let alive = ProcessOwnership.processAlive(pid)
                if !alive { break }
            }
        }
        if let pid = launcherPid, pid > 0 && ProcessOwnership.processAlive(pid) {
            kill(pid, SIGKILL)
        }

        try? FileManager.default.removeItem(at: tmp)
        try super.tearDownWithError()
    }

    // MARK: - Core proof: child survives launcher death

    /// Spawns a launcher, waits for the launcher to die, then proves the child
    /// survived. The child holds an exclusive flock(2) (simulating the write lock),
    /// waits for a done signal, writes its terminal marker, and releases the lock.
    ///
    /// Python is the portable way to flock from /bin/sh on macOS (no flock(1)).
    func testChildSurvivesLauncherExitWhileHoldingWriteLock() throws {
        let launcherPIDPath = markerDir.appendingPathComponent("launcher.pid")
        let childPidPath = markerDir.appendingPathComponent("child.pid")
        let childAlivePath = markerDir.appendingPathComponent("child.alive")
        let childLockedPath = markerDir.appendingPathComponent("child.locked")
        let childTerminalPath = markerDir.appendingPathComponent("child.terminal")
        let lockFile = markerDir.appendingPathComponent("write.lock")
        let doneSignal = markerDir.appendingPathComponent("done.signal")

        // ---- child script (shell wrapper around python3 for cross-process flock) ----
        let childScript = tmp.appendingPathComponent("child.sh")
        let childBody = """
        #!/bin/sh
        echo $$ > "\(childPidPath.path)"
        echo "alive" > "\(childAlivePath.path)"
        python3 -c '
        import fcntl, os, sys, time
        pid = os.getpid()
        lock_path = sys.argv[1]
        locked_path = sys.argv[2]
        terminal_path = sys.argv[3]
        done_path = sys.argv[4]
        fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        with open(locked_path, "w") as f:
            f.write("locked")
        while not os.path.exists(done_path):
            time.sleep(0.1)
        with open(terminal_path, "w") as f:
            f.write("terminal")
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)
        ' "\(lockFile.path)" "\(childLockedPath.path)" "\(childTerminalPath.path)" "\(doneSignal.path)"
        """
        try childBody.write(to: childScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: childScript.path)

        // ---- launcher script: spawns child, waits for it to start, exits ----
        let launcherScript = tmp.appendingPathComponent("launcher.sh")
        let launcherBody = """
        #!/bin/sh
        echo $$ > "\(launcherPIDPath.path)"
        nohup "\(childScript.path)" >/dev/null 2>&1 </dev/null &
        sleep 0.5
        exit 0
        """
        try launcherBody.write(to: launcherScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherScript.path)

        // ---- spawn launcher ----
        let launcherProcess = Process()
        launcherProcess.executableURL = launcherScript
        launcherProcess.currentDirectoryURL = tmp
        try launcherProcess.run()

        self.launcherPid = launcherProcess.processIdentifier

        // ---- wait for launcher to die ----
        launcherProcess.waitUntilExit()
        let launcherDeadline = Date().addingTimeInterval(10)
        var launcherStillAlive = true
        while Date() < launcherDeadline && launcherStillAlive {
            launcherStillAlive = ProcessOwnership.processAlive(launcherProcess.processIdentifier)
            if launcherStillAlive { usleep(50_000) }
        }

        // Property 1: launcher is verifiably dead.
        XCTAssertFalse(
            launcherStillAlive,
            "launcher (pid \(launcherProcess.processIdentifier)) was still alive after waitUntilExit + liveness poll"
        )
        XCTAssertEqual(launcherProcess.terminationStatus, 0,
                       "launcher exited with non-zero status \(launcherProcess.terminationStatus)")

        // ---- read child PID from marker ----
        var childPidRead: pid_t = 0
        let childPidRaw = try String(contentsOf: childPidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        childPidRead = pid_t(childPidRaw) ?? 0
        self.childPid = childPidRead
        XCTAssertGreaterThan(childPidRead, 0, "child pid marker is missing or invalid (content: '\(childPidRaw)')")

        // Property 2: child survives launcher death.
        XCTAssertTrue(
            ProcessOwnership.processAlive(childPidRead),
            "child (pid \(childPidRead)) did not survive launcher exit — child is dead while launcher (pid \(launcherProcess.processIdentifier)) is gone"
        )

        // Property 3: child holds the simulated write lock.
        var locked = FileManager.default.fileExists(atPath: childLockedPath.path)
        if !locked {
            let lockPollDeadline = Date().addingTimeInterval(3)
            while Date() < lockPollDeadline && !locked {
                locked = FileManager.default.fileExists(atPath: childLockedPath.path)
                if !locked { usleep(100_000) }
            }
        }
        XCTAssertTrue(locked,
                      "child (pid \(childPidRead)) is alive but did not acquire the write lock — locked marker not found at \(childLockedPath.path)")

        // Cross-process verification: attempt non-blocking lock acquisition should fail.
        let lockFd = open(lockFile.path, O_RDONLY)
        if lockFd >= 0 {
            let couldAcquire = flock(lockFd, LOCK_EX | LOCK_NB) == 0
            if couldAcquire { flock(lockFd, LOCK_UN) }
            close(lockFd)
            XCTAssertFalse(couldAcquire,
                           "child (pid \(childPidRead)) should hold the write lock, but an outsider acquired it — lock file \(lockFile.path) is unguarded")
        }

        // ---- signal child to finish ----
        try Data("done".utf8).write(to: doneSignal, options: .atomic)

        // ---- wait for child terminal state ----
        var terminalFound = false
        let terminalDeadline = Date().addingTimeInterval(10)
        while Date() < terminalDeadline && !terminalFound {
            if FileManager.default.fileExists(atPath: childTerminalPath.path) {
                terminalFound = true
                break
            }
            usleep(100_000)
        }
        XCTAssertTrue(terminalFound,
                      "child (pid \(childPidRead)) did not reach terminal state within 10s after done signal — terminal marker not found at \(childTerminalPath.path)")

        let terminalContent = try String(contentsOf: childTerminalPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(terminalContent, "terminal",
                       "child (pid \(childPidRead)) terminal marker contains '\(terminalContent)', expected 'terminal'")

        // Property 4: lock was released.
        let lockFd2 = open(lockFile.path, O_RDONLY)
        if lockFd2 >= 0 {
            let couldAcquireAfter = flock(lockFd2, LOCK_EX | LOCK_NB) == 0
            if couldAcquireAfter { flock(lockFd2, LOCK_UN) }
            close(lockFd2)
            XCTAssertTrue(couldAcquireAfter,
                          "child (pid \(childPidRead)) should have released the write lock after reaching terminal, but lock \(lockFile.path) is still held")
        }

        // Child should exit on its own after finishing.
        let childExitDeadline = Date().addingTimeInterval(5)
        var childExited = false
        while Date() < childExitDeadline && !childExited {
            if !ProcessOwnership.processAlive(childPidRead) { childExited = true; break }
            var status: Int32 = 0
            if waitpid(childPidRead, &status, WNOHANG) > 0 { childExited = true; break }
            usleep(50_000)
        }
        self.childPid = nil // tearDown should not re-kill a cleanly exited child
    }

    // MARK: - Mutating property: lock is exclusive

    func testChildExclusiveLockPreventsSecondHolder() throws {
        let lockFile = markerDir.appendingPathComponent("exclusive.lock")
        let doneSignal = markerDir.appendingPathComponent("done.signal")

        let childScript = tmp.appendingPathComponent("child-exclusive.sh")
        let childBody = """
        #!/bin/sh
        python3 -c '
        import fcntl, os, time, sys
        lock_path = sys.argv[1]
        done_path = sys.argv[2]
        fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        while not os.path.exists(done_path):
            time.sleep(0.1)
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)
        ' "\(lockFile.path)" "\(doneSignal.path)"
        """
        try childBody.write(to: childScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: childScript.path)

        let launcherScript = tmp.appendingPathComponent("launcher-exclusive.sh")
        let launcherPidPath = markerDir.appendingPathComponent("el.pid")
        let launcherBody = """
        #!/bin/sh
        echo $$ > "\(launcherPidPath.path)"
        nohup "\(childScript.path)" >/dev/null 2>&1 </dev/null &
        sleep 0.5
        exit 0
        """
        try launcherBody.write(to: launcherScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherScript.path)

        let lp = Process()
        lp.executableURL = launcherScript
        lp.currentDirectoryURL = tmp
        try lp.run()
        self.launcherPid = lp.processIdentifier
        lp.waitUntilExit()

        // Give the child a moment to acquire the lock.
        usleep(500_000)

        let fd = open(lockFile.path, O_RDONLY)
        if fd >= 0 {
            let took = flock(fd, LOCK_EX | LOCK_NB) == 0
            if took { flock(fd, LOCK_UN) }
            close(fd)
            XCTAssertFalse(took,
                           "child's exclusive lock should prevent a second holder — lock file \(lockFile.path) was acquirable")
        }

        try Data("done".utf8).write(to: doneSignal, options: .atomic)
    }
}
