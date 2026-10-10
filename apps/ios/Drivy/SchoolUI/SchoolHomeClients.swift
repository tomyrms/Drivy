import Foundation

/// The clients of the signed-in shell, created once for the app with one shared transport
/// (one URLSession), instead of a new session at every render of the root.
@MainActor final class SchoolHomeClients {
    let transport: any SchoolHTTPTransport
    let agenda: SchoolAgendaClient
    let training: SchoolTrainingClient

    init(configuration: AppConfiguration, tokenSource: any AccessTokenSource,
         transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.transport = transport
        agenda = SchoolAgendaClient(baseURL: configuration.apiBaseURL, tokenSource: tokenSource, transport: transport)
        training = SchoolTrainingClient(baseURL: configuration.apiBaseURL, tokenSource: tokenSource, transport: transport)
    }
}
