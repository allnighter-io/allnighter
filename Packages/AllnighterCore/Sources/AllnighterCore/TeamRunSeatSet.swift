import Foundation

/// Shared seat-set law for team artifacts and the Factory Floor (TRR-S01 / G11).
/// Seat chips include answer, review, and plan workers in `workers[]` declaration
/// order; scout and other stages are excluded from the card seat set.
public enum TeamRunSeatSet {
    public static func workers(for run: TeamRun) -> [Worker] {
        run.workers.filter(isSeatWorker)
    }

    public static func isSeatWorker(_ worker: Worker) -> Bool {
        guard let purpose = worker.purpose else { return true } // legacy → answer
        switch purpose {
        case .answer, .review, .plan: return true
        case .scout: return false
        }
    }
}
