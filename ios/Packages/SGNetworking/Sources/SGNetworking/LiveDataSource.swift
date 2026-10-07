import Foundation
import SGModels

public struct LiveDataSource: GrantsDataSource {
    public let baseURL: URL
    public let apiKey: String?
    public let token: String?

    let tokenStore: any TokenStore
    private let client: APIClient

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:8080")!,
        apiKey: String? = "local-dev-api-key",
        token: String? = nil
    ) {
        let tokenStore = InMemoryTokenStore(token: token)
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.token = token
        self.tokenStore = tokenStore
        client = APIClient(baseURL: baseURL, apiKey: apiKey, tokenStore: tokenStore)
    }

    public init(
        baseURL: URL,
        apiKey: String?,
        tokenStore: any TokenStore,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        token = tokenStore.load()
        self.tokenStore = tokenStore
        client = APIClient(baseURL: baseURL, apiKey: apiKey, tokenStore: tokenStore, session: session)
    }

    public func searchOpportunities(_ request: SearchRequest) async throws -> SearchResponse {
        var request = request
        if request.pagination.sortOrder.isEmpty {
            request = SearchRequest(
                query: request.query,
                queryOperator: request.queryOperator,
                filters: request.filters,
                pagination: SearchPagination(
                    pageOffset: request.pagination.pageOffset,
                    pageSize: request.pagination.pageSize,
                    sortOrder: [SortOrder(orderBy: "relevancy", sortDirection: "descending")]
                )
            )
        }
        let data = try await client.data(
            path: "/v1/opportunities/search",
            method: "POST",
            body: try JSONEncoder.sg.encode(request),
            authRequirement: .jwtOrAPIKey
        )
        let response = try decode(Envelope<[Opportunity]>.self, from: data)
        guard let opportunities = response.data else {
            throw GrantsError.decoding("Search response did not include data.")
        }
        return SearchResponse(
            data: opportunities,
            paginationInfo: response.paginationInfo ?? PaginationInfo(),
            facetCounts: response.facetCounts ?? [:]
        )
    }

    public func opportunity(id: String) async throws -> OpportunityDetail {
        try await get(path: "/v1/opportunities/\(id)", authRequirement: .jwtOrAPIKey)
    }

    public func currentUser() async throws -> UserProfile {
        let userId = try await client.userId()
        return try await get(path: "/v1/users/\(userId)", authRequirement: .userJWT)
    }

    public func organizations() async throws -> [Organization] {
        let userId = try await client.userId()
        return try await get(path: "/v1/users/\(userId)/organizations", authRequirement: .userJWT)
    }

    public func applications() async throws -> [ApplicationSummary] {
        let userId = try await client.userId()
        var offset = 1
        var applications: [ApplicationSummary] = []
        while true {
            let data = try await client.data(
                path: "/v1/users/\(userId)/applications",
                method: "POST",
                body: try JSONEncoder.sg.encode(
                    PaginationRequest(
                        pageOffset: offset,
                        pageSize: 100,
                        sortOrder: [SortOrder(orderBy: "created_at", sortDirection: "descending")]
                    )
                ),
                authRequirement: .userJWT
            )
            let response = try decode(Envelope<[ApplicationSummary]>.self, from: data)
            let page = try response.requiredData()
            applications.append(contentsOf: page)
            guard
                let totalPages = response.paginationInfo?.totalPages,
                offset < totalPages,
                !page.isEmpty
            else {
                break
            }
            offset += 1
        }
        return applications
    }

    public func startApplication(
        competitionId: String,
        name: String,
        organizationId: String?
    ) async throws -> String {
        let response: ApplicationStart = try await post(
            path: "/alpha/applications/start",
            body: ApplicationStartRequest(
                competitionId: competitionId,
                applicationName: name,
                organizationId: organizationId
            ),
            authRequirement: .userJWT
        )
        return response.applicationId
    }

    public func application(id: String) async throws -> Application {
        try await get(path: "/alpha/applications/\(id)", authRequirement: .userJWT)
    }

    public func form(id: String) async throws -> FormDefinition {
        try await get(path: "/alpha/forms/\(id)", authRequirement: .apiKey)
    }

    public func saveForm(
        applicationId: String,
        formId: String,
        response: JSONValue
    ) async throws -> FormSaveResult {
        let data = try await client.data(
            path: "/alpha/applications/\(applicationId)/forms/\(formId)",
            method: "PUT",
            body: try JSONEncoder.sg.encode(FormResponseRequest(applicationResponse: response)),
            authRequirement: .userJWT
        )
        let envelope = try decode(Envelope<ApplicationForm>.self, from: data)
        guard let form = envelope.data else {
            throw GrantsError.decoding("Form save response did not include the saved form.")
        }
        return FormSaveResult(warnings: envelope.warnings ?? [], form: form)
    }

    public func submit(applicationId: String) async throws -> SubmissionResult {
        _ = try await client.data(
            path: "/alpha/applications/\(applicationId)/submit",
            method: "POST",
            authRequirement: .userJWT
        )
        let submissions: [SubmissionRecord]? = try? await post(
            path: "/alpha/applications/\(applicationId)/submissions",
            body: PaginationRequest(
                pageOffset: 1,
                pageSize: 1,
                sortOrder: [SortOrder(orderBy: "created_at", sortDirection: "descending")]
            ),
            authRequirement: .userJWT
        )
        return SubmissionResult(
            applicationId: applicationId,
            trackingNumber: submissions?.first?.legacyTrackingNumber.map(String.init)
        )
    }

    public func savedOpportunityIds() async throws -> Set<String> {
        let userId = try await client.userId()
        var offset = 1
        var identifiers = Set<String>()
        while true {
            let data = try await client.data(
                path: "/v1/users/\(userId)/saved-opportunities/list",
                method: "POST",
                body: try JSONEncoder.sg.encode(
                    PaginationRequest(
                        pageOffset: offset,
                        pageSize: 100,
                        sortOrder: [SortOrder(orderBy: "created_at", sortDirection: "descending")]
                    )
                ),
                authRequirement: .userJWT
            )
            let response = try decode(Envelope<[SavedOpportunity]>.self, from: data)
            let page = response.data ?? []
            identifiers.formUnion(page.map(\.opportunityId))
            guard let totalPages = response.paginationInfo?.totalPages, offset < totalPages, !page.isEmpty else {
                break
            }
            offset += 1
        }
        return identifiers
    }

    public func setSaved(_ saved: Bool, opportunityId: String) async throws {
        let userId = try await client.userId()
        if saved {
            _ = try await client.data(
                path: "/v1/users/\(userId)/saved-opportunities",
                method: "POST",
                body: try JSONEncoder.sg.encode(SaveOpportunityRequest(opportunityId: opportunityId)),
                authRequirement: .userJWT
            )
        } else {
            do {
                _ = try await client.data(
                    path: "/v1/users/\(userId)/saved-opportunities/\(opportunityId)",
                    method: "DELETE",
                    authRequirement: .userJWT
                )
            } catch GrantsError.notFound {
                return
            }
        }
    }

    private func get<T: Decodable>(
        path: String,
        authRequirement: APIAuthRequirement
    ) async throws -> T {
        let data = try await client.data(path: path, authRequirement: authRequirement)
        return try decode(Envelope<T>.self, from: data).requiredData()
    }

    private func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        authRequirement: APIAuthRequirement
    ) async throws -> Response {
        let data = try await client.data(
            path: path,
            method: "POST",
            body: try JSONEncoder.sg.encode(body),
            authRequirement: authRequirement
        )
        return try decode(Envelope<Response>.self, from: data).requiredData()
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder.sg.decode(type, from: data)
        } catch {
            throw GrantsError.decoding(error.localizedDescription)
        }
    }
}

private struct Envelope<Value: Decodable>: Decodable {
    let message: String?
    let data: Value?
    let paginationInfo: PaginationInfo?
    let facetCounts: [String: [String: Int]]?
    let warnings: [ValidationWarning]?

    func requiredData() throws -> Value {
        guard let data else { throw GrantsError.decoding("The response did not include data.") }
        return data
    }
}

private struct PaginationRequest: Encodable {
    private let pagination: Pagination

    init(pageOffset: Int, pageSize: Int, sortOrder: [SGModels.SortOrder]) {
        pagination = Pagination(pageOffset: pageOffset, pageSize: pageSize, sortOrder: sortOrder)
    }

    private struct Pagination: Encodable {
        let pageOffset: Int
        let pageSize: Int
        let sortOrder: [SGModels.SortOrder]
    }
}

private struct ApplicationStartRequest: Encodable {
    let competitionId: String
    let applicationName: String
    let organizationId: String?
}

private struct ApplicationStart: Decodable {
    let applicationId: String
}

private struct FormResponseRequest: Encodable {
    let applicationResponse: JSONValue
}

private struct SubmissionRecord: Decodable {
    let legacyTrackingNumber: Int?
}

private struct SavedOpportunity: Decodable {
    let opportunityId: String
}

private struct SaveOpportunityRequest: Encodable {
    let opportunityId: String
}
