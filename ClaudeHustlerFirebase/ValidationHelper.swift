// ValidationHelper.swift
// Comprehensive input validation and sanitization utilities

import Foundation
import UIKit
import CommonCrypto

struct ValidationHelper {
    
    // MARK: - Email Validation
    static func validateEmail(_ email: String) -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Basic checks
        guard !trimmedEmail.isEmpty,
              trimmedEmail.count <= 255,
              trimmedEmail.contains("@") else {
            return false
        }
        
        // RFC 5322 compliant email regex
        let emailRegex = #"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"#
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        
        return emailPredicate.evaluate(with: trimmedEmail)
    }
    
    // MARK: - Password Validation
    static func validatePassword(_ password: String) -> (valid: Bool, errors: [String]) {
        var errors: [String] = []
        
        // Length check
        if password.count < 8 {
            errors.append("Password must be at least 8 characters")
        }
        if password.count > 128 {
            errors.append("Password too long (max 128 characters)")
        }
        
        // Complexity checks
        let hasUppercase = password.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasLowercase = password.range(of: "[a-z]", options: .regularExpression) != nil
        let hasDigit = password.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSpecialChar = password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil
        
        if !hasUppercase {
            errors.append("Password must contain at least one uppercase letter")
        }
        if !hasLowercase {
            errors.append("Password must contain at least one lowercase letter")
        }
        if !hasDigit {
            errors.append("Password must contain at least one number")
        }
        if !hasSpecialChar {
            errors.append("Password must contain at least one special character")
        }
        
        // Check for common passwords
        let commonPasswords = ["password", "12345678", "qwerty", "abc123", "password123"]
        if commonPasswords.contains(password.lowercased()) {
            errors.append("Password is too common")
        }
        
        // Check for whitespace
        if password.contains(" ") {
            errors.append("Password cannot contain spaces")
        }
        
        return (errors.isEmpty, errors)
    }
    
    // MARK: - Input Sanitization
    static func sanitizeInput(_ input: String, maxLength: Int = 1000) -> String {
        var sanitized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove control characters
        sanitized = sanitized.components(separatedBy: CharacterSet.controlCharacters).joined()
        
        // Strip HTML/Script tags
        sanitized = stripHTML(sanitized)
        
        // Escape special characters for Firebase
        sanitized = sanitized
            .replacingOccurrences(of: "'", with: "\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        
        // Truncate to max length
        if sanitized.count > maxLength {
            let index = sanitized.index(sanitized.startIndex, offsetBy: maxLength)
            sanitized = String(sanitized[..<index])
        }
        
        return sanitized
    }
    
    // MARK: - HTML Stripping
    static func stripHTML(_ text: String) -> String {
        // Remove all HTML tags
        var stripped = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression,
            range: nil
        )
        
        // Decode HTML entities
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&nbsp;": " "
        ]
        
        for (entity, replacement) in entities {
            stripped = stripped.replacingOccurrences(of: entity, with: replacement)
        }
        
        // Remove script content
        stripped = stripped.replacingOccurrences(
            of: "<script[^>]*>.*?</script>",
            with: "",
            options: [.regularExpression, .caseInsensitive],
            range: nil
        )
        
        return stripped
    }
    
    // MARK: - Image Validation
    static func validateImageData(_ data: Data) -> (valid: Bool, error: String?) {
        // Check file size (max 10MB)
        let maxSize = 10 * 1024 * 1024 // 10MB in bytes
        if data.count > maxSize {
            return (false, "Image must be less than 10MB")
        }
        
        // Check file type
        guard let image = UIImage(data: data) else {
            return (false, "Invalid image format")
        }
        
        // Validate image format (JPEG or PNG)
        let imageTypes: [CFString] = [kUTTypeJPEG, kUTTypePNG]
        var isValidType = false
        
        if let cgImage = image.cgImage {
            // Check if it's a valid image format
            if data.count > 0 {
                // Check for JPEG signature
                let jpegSignature: [UInt8] = [0xFF, 0xD8, 0xFF]
                let jpegData = data.prefix(3)
                if jpegData.elementsEqual(jpegSignature) {
                    isValidType = true
                }
                
                // Check for PNG signature
                let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
                let pngData = data.prefix(8)
                if pngData.elementsEqual(pngSignature) {
                    isValidType = true
                }
            }
        }
        
        if !isValidType {
            return (false, "Only JPEG and PNG images are supported")
        }
        
        // Check image dimensions
        if let size = image.size as CGSize? {
            let maxDimension: CGFloat = 10000
            if size.width > maxDimension || size.height > maxDimension {
                return (false, "Image dimensions too large (max 10000x10000)")
            }
            
            if size.width < 10 || size.height < 10 {
                return (false, "Image too small (min 10x10)")
            }
        }
        
        return (true, nil)
    }
    
    // MARK: - Image Compression
    static func compressImage(_ image: UIImage, maxDimension: CGFloat = 1920, quality: CGFloat = 0.8) -> Data? {
        // Calculate new size
        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        
        // Don't upscale
        if ratio >= 1.0 {
            return image.jpegData(compressionQuality: quality)
        }
        
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        // Resize image
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // Compress to JPEG
        guard let resized = resizedImage else { return nil }
        var compressionQuality = quality
        var imageData = resized.jpegData(compressionQuality: compressionQuality)
        
        // Further compress if still too large
        let maxFileSize = 5 * 1024 * 1024 // 5MB
        while let data = imageData, data.count > maxFileSize && compressionQuality > 0.1 {
            compressionQuality -= 0.1
            imageData = resized.jpegData(compressionQuality: compressionQuality)
        }
        
        return imageData
    }
    
    // MARK: - Generate Thumbnail
    static func generateThumbnail(from image: UIImage, size: CGFloat = 200) -> UIImage? {
        let targetSize = CGSize(width: size, height: size)
        
        // Calculate aspect fit size
        let widthRatio = targetSize.width / image.size.width
        let heightRatio = targetSize.height / image.size.height
        let ratio = min(widthRatio, heightRatio)
        
        let newSize = CGSize(
            width: image.size.width * ratio,
            height: image.size.height * ratio
        )
        
        // Create thumbnail
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        
        // Fill with background color
        UIColor.systemBackground.setFill()
        UIRectFill(CGRect(origin: .zero, size: targetSize))
        
        // Draw image centered
        let rect = CGRect(
            x: (targetSize.width - newSize.width) / 2,
            y: (targetSize.height - newSize.height) / 2,
            width: newSize.width,
            height: newSize.height
        )
        image.draw(in: rect)
        
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return thumbnail
    }
    
    // MARK: - Username Validation
    static func validateUsername(_ username: String) -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Length check
        guard trimmed.count >= 3 && trimmed.count <= 30 else {
            return false
        }
        
        // Allowed characters: letters, numbers, underscore, dash
        let usernameRegex = "^[a-zA-Z0-9_-]+$"
        let usernamePredicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
        
        // Must start with letter or number
        let firstChar = trimmed.first
        guard let first = firstChar, first.isLetter || first.isNumber else {
            return false
        }
        
        return usernamePredicate.evaluate(with: trimmed)
    }
    
    // MARK: - Phone Number Validation
    static func validatePhoneNumber(_ phone: String) -> Bool {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common formatting characters
        let digits = trimmed.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        
        // Check length (10-15 digits for international)
        guard digits.count >= 10 && digits.count <= 15 else {
            return false
        }
        
        // Basic international phone regex
        let phoneRegex = #"^[\+]?[(]?[0-9]{1,3}[)]?[-\s\.]?[(]?[0-9]{1,4}[)]?[-\s\.]?[0-9]{1,4}[-\s\.]?[0-9]{1,9}$"#
        let phonePredicate = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        
        return phonePredicate.evaluate(with: trimmed)
    }
    
    // MARK: - URL Validation
    static func validateURL(_ urlString: String) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if URL can be created
        guard let url = URL(string: trimmed),
              let scheme = url.scheme else {
            return false
        }
        
        // Ensure HTTPS for security
        guard scheme == "https" || scheme == "http" else {
            return false
        }
        
        // Additional validation
        let urlRegex = #"^(https?://)?([\da-z\.-]+)\.([a-z\.]{2,6})([/\w \.-]*)*/?$"#
        let urlPredicate = NSPredicate(format: "SELF MATCHES %@", urlRegex)
        
        return urlPredicate.evaluate(with: trimmed)
    }
    
    // MARK: - Profanity Filter
    static func containsProfanity(_ text: String) -> Bool {
        // Basic profanity list (expand as needed)
        let profanityList = [
            "fuck", "shit", "ass", "damn", "hell", "bitch", "bastard",
            "crap", "piss", "dick", "cock", "pussy", "asshole", "fag",
            "nigger", "cunt", "slut", "whore"
        ]
        
        let lowercased = text.lowercased()
        
        for word in profanityList {
            if lowercased.contains(word) {
                return true
            }
        }
        
        // Check for leetspeak variations
        let leetVariations = [
            "f[u|v]ck", "sh[i|1]t", "[a|@]ss", "b[i|1]tch",
            "d[i|1]ck", "c[o|0]ck", "p[u|v]ssy"
        ]
        
        for pattern in leetVariations {
            if lowercased.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Text Length Validation
    static func validateTextLength(_ text: String, min: Int = 0, max: Int) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= min && trimmed.count <= max
    }
    
    // MARK: - Credit Card Validation (Luhn Algorithm)
    static func validateCreditCard(_ number: String) -> Bool {
        let digits = number.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        
        // Check length
        guard digits.count >= 13 && digits.count <= 19 else {
            return false
        }
        
        // Luhn algorithm
        var sum = 0
        let reversedDigits = digits.reversed().map { Int(String($0))! }
        
        for (index, digit) in reversedDigits.enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        
        return sum % 10 == 0
    }
    
    // MARK: - Date Validation
    static func validateDate(_ date: Date, minDate: Date? = nil, maxDate: Date? = nil) -> Bool {
        if let min = minDate, date < min {
            return false
        }
        if let max = maxDate, date > max {
            return false
        }
        return true
    }
    
    // MARK: - Coordinate Validation
    static func validateCoordinates(latitude: Double, longitude: Double) -> Bool {
        return latitude >= -90 && latitude <= 90 &&
               longitude >= -180 && longitude <= 180
    }
    
    // MARK: - File Extension Validation
    static func validateFileExtension(_ filename: String, allowedExtensions: [String]) -> Bool {
        guard let fileExtension = filename.split(separator: ".").last?.lowercased() else {
            return false
        }
        
        return allowedExtensions.map { $0.lowercased() }.contains(String(fileExtension))
    }
    
    // MARK: - JSON Validation
    static func isValidJSON(_ string: String) -> Bool {
        guard let data = string.data(using: .utf8) else {
            return false
        }
        
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [])
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Hash Password (for local validation only)
    static func hashPassword(_ password: String) -> String {
        // Use SHA256 for local validation (Firebase handles actual password hashing)
        guard let data = password.data(using: .utf8) else {
            return ""
        }
        
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
