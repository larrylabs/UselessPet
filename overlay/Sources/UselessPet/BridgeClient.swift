import Foundation
import Combine

/// Authenticated local companion client. Reconnects with backoff and reads
/// the current per-run token before every connection attempt.
@MainActor
final class BridgeClient: ObservableObject {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
    }

    enum TransientEvent: Equatable {
        case petted(id: UUID, reaction: CompanionReaction = .joy)
        var displayDuration: TimeInterval { CompanionReaction.duration }
    }

    @Published private(set) var status: Status = .disconnected
    @Published private(set) var pet: PetState = .placeholder
    @Published private(set) var transient: TransientEvent? = nil
    @Published private(set) var activity: ActivityState = .idle
    @Published private(set) var pendingSpecies: String?
    @Published private(set) var companionFeedback: L10nKey?
    private var switchTimeout: Task<Void, Never>?

    var statusText: String {
        switch status {
        case .disconnected: return "offline"
        case .connecting:   return "connecting…"
        case .connected:    return "connected"
        }
    }

    private let url = ConnectionSettings.url
    private var task: URLSessionWebSocketTask?
    private let session: URLSession = .shared
    private let prepareConnection: () -> Void
    private var backoff: TimeInterval = 1.0
    private var transientClearTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var pendingPing: UUID?

    private static let decoder = JSONDecoder()

    init(prepareConnection: @escaping () -> Void = {}) {
        self.prepareConnection = prepareConnection
    }

    func connect() {
        guard task == nil else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        prepareConnection()
        status = .connecting
        var request = URLRequest(url: url)
        let token = (try? String(contentsOf: ConnectionSettings.tokenFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        receiveLoop(on: task)
        startHeartbeat(on: task)
    }

    func disconnect() {
        finishSwitch(message: pendingSpecies == nil ? nil : .disconnected)
        let previous = task
        task = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        pendingPing = nil
        previous?.cancel(with: .goingAway, reason: nil)
        status = .disconnected
    }

    /// Send a supported companion command to the daemon.
    func send(command type: String, args: [String: Any] = [:]) {
        guard status == .connected, let task else { return }
        let envelope: [String: Any] = ["type": type, "args": args]
        guard
            let data = try? JSONSerialization.data(withJSONObject: envelope),
            let str = String(data: data, encoding: .utf8)
        else { return }
        task.send(.string(str)) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.scheduleReconnect(after: task) }
        }
    }

    // MARK: - private

    func switchCompanion(to id: String) {
        guard status == .connected, pendingSpecies == nil,
              SpeciesCatalog.pickableIds.contains(id) else { return }
        guard id != pet.speciesId else { return }
        pendingSpecies = id
        companionFeedback = nil
        send(command: "cmd.switch_species", args: ["species_id": id])
        switchTimeout?.cancel()
        switchTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            self?.finishSwitch(message: .switchFailed)
        }
    }

    private func finishSwitch(message: L10nKey?) {
        switchTimeout?.cancel()
        switchTimeout = nil
        pendingSpecies = nil
        companionFeedback = message
    }

    private func markConnected() {
        status = .connected
        backoff = 1.0
    }

    private func receiveLoop(on socket: URLSessionWebSocketTask) {
        socket.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                guard self.task === socket else { return }
                switch result {
                case .success(let message):
                    self.handle(message: message)
                    self.receiveLoop(on: socket)
                case .failure:
                    self.scheduleReconnect(after: socket)
                }
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        let raw: Data
        switch message {
        case .string(let s):
            raw = Data(s.utf8)
        case .data(let d):
            raw = d
        @unknown default:
            return
        }
        decode(raw: raw)
    }

    private func decode(raw: Data) {
        // Peek at the type field
        guard
            let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
            let type = json["type"] as? String
        else { return }

        let payload = (json["payload"] as? [String: Any]) ?? [:]
        switch type {
        case "state.snapshot":
            if json["service"] as? String == "UselessPet", let stateBlob = json["state"] as? [String: Any],
               let stateData = try? JSONSerialization.data(withJSONObject: stateBlob),
               let parsed = try? Self.decoder.decode(PetState.self, from: stateData) {
                self.markConnected()
                self.pet = parsed
                if parsed.speciesId == pendingSpecies { finishSwitch(message: nil) }
            }
        case "event.species_changed":
            if payload["changed"] as? Bool == false, payload["reason"] as? String != "no_op", pendingSpecies != nil {
                finishSwitch(message: .switchFailed)
            }
        case "event.petted":
            let reaction = CompanionReaction(rawValue: payload["reaction"] as? String ?? "") ?? .joy
            companionFeedback = reaction.feedback
            triggerTransient(.petted(id: UUID(), reaction: reaction))
        case "command.error":
            finishSwitch(message: .switchFailed)
        default:
            break
        }
    }

    private func triggerTransient(_ event: TransientEvent) {
        transient = event
        transientClearTask?.cancel()
        let nanos = UInt64(event.displayDuration * 1_000_000_000)
        transientClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanos)
            if !Task.isCancelled {
                transient = nil
                if pendingSpecies == nil { companionFeedback = nil }
            }
        }
    }

    /// A half-closed server can leave receive() pending indefinitely. Ping
    /// frames check liveness without issuing commands or changing pet state.
    private func startHeartbeat(on socket: URLSessionWebSocketTask) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 5_000_000_000) }
                catch { return }
                guard let self, self.task === socket else { return }
                let ping = UUID()
                self.pendingPing = ping
                socket.sendPing { [weak self] error in
                    Task { @MainActor in
                        guard let self, self.task === socket, self.pendingPing == ping else { return }
                        if error != nil { self.scheduleReconnect(after: socket) }
                        else { self.pendingPing = nil }
                    }
                }
                do { try await Task.sleep(nanoseconds: 3_000_000_000) }
                catch { return }
                guard self.task === socket else { return }
                if self.pendingPing == ping {
                    self.scheduleReconnect(after: socket)
                    return
                }
            }
        }
    }

    private func scheduleReconnect(after socket: URLSessionWebSocketTask) {
        // Discard late callbacks from an older connection. Only one pending
        // reconnect may own the next socket and connection attempt.
        guard task === socket else { return }
        finishSwitch(message: pendingSpecies == nil ? nil : .disconnected)
        status = .disconnected
        task = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        pendingPing = nil
        // Recovery must abort the old transport. A close handshake can itself
        // hang when the peer has already stopped processing WebSocket frames.
        socket.cancel()
        let delay = min(backoff, 30.0)
        backoff = min(backoff * 2, 30.0)
        reconnectTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            self.reconnectTask = nil
            self.connect()
        }
    }
}
