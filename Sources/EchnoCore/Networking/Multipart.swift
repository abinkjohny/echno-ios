import Foundation

/// One part of a `multipart/form-data` body.
///
/// The generated client handles ordinary JSON request bodies. Multipart is the
/// exception worth keeping by hand: the attendance endpoints send the DTO as a
/// `data` text part alongside a file part, and that file part is named `photo`
/// on the `/web` controllers but `photoUrl` on the mobile ones — optional on
/// both, so the wrong name returns 201 having quietly dropped the photo. See
/// `local-docs/backend-mobile-api-gaps.md` §4.2a before wiring check-in.
public struct MultipartPart: Sendable {
    public let name: String
    public let filename: String?
    public let contentType: String?
    public let data: Data

    public init(name: String, filename: String?, contentType: String?, data: Data) {
        self.name = name
        self.filename = filename
        self.contentType = contentType
        self.data = data
    }

    /// A plain text or JSON field.
    public static func text(_ name: String, _ value: String) -> MultipartPart {
        MultipartPart(name: name, filename: nil, contentType: nil, data: Data(value.utf8))
    }

    /// A file field.
    public static func file(
        _ name: String,
        filename: String,
        contentType: String,
        data: Data
    ) -> MultipartPart {
        MultipartPart(name: name, filename: filename, contentType: contentType, data: data)
    }

    /// Encodes `parts` into a body for the given boundary.
    public static func encode(_ parts: [MultipartPart], boundary: String) -> Data {
        var body = Data()
        for part in parts {
            body.append(Data("--\(boundary)\r\n".utf8))
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            body.append(Data("\(disposition)\r\n".utf8))
            if let contentType = part.contentType {
                body.append(Data("Content-Type: \(contentType)\r\n".utf8))
            }
            body.append(Data("\r\n".utf8))
            body.append(part.data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    /// A fresh boundary token.
    public static func boundary() -> String { "echno.\(UUID().uuidString)" }
}
