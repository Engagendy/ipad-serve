import Foundation

enum MimeTypes {
    static func type(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js", "mjs": return "application/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "pdf": return "application/pdf"
        case "mov": return "video/quicktime"
        case "mp4", "m4v": return "video/mp4"
        case "webm": return "video/webm"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "m4a": return "audio/mp4"
        case "aac": return "audio/aac"
        case "ogg", "oga": return "audio/ogg"
        case "opus": return "audio/opus"
        case "flac": return "audio/flac"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "avif": return "image/avif"
        case "heic": return "image/heic"
        case "bmp": return "image/bmp"
        case "txt", "md": return "text/plain; charset=utf-8"
        case "xml": return "application/xml; charset=utf-8"
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }
}
