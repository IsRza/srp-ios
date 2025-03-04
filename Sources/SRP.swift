import Foundation
import Cryptor
import BigInt

/// Creates the salted verification key based on a user's username and
/// password. Only the salt and verification key need to be stored on the
/// server, there's no need to keep the plain-text password. 
///
/// Keep the verification key private, as it can be used to brute-force 
/// the password from.
///
/// - Parameters:
///   - username: user's username
///   - password: user's password
///   - salt: (optional) custom salt value; if providing a salt, make sure to
///       provide a good random salt of at least 16 bytes. Default is to
///       generate a salt of 16 bytes.
///   - group: `Group` parameters; default is 2048-bits group.
///   - algorithm: which `Digest.Algorithm` to use; default is SHA1.
/// - Returns: salt (s) and verification key (v)
public func createSaltedVerificationKey(
    clientType: ClientType,
    username: String,
    password: String,
    salt: Data? = nil,
    group: Group = .N2048,
    algorithm: Digest.Algorithm = .sha1)
    -> (salt: Data, verificationKey: Data)
{
    let salt = salt ?? randomBytes(16)
    
    let x: BigUInt
    
    switch clientType {
    case .nimbus:
        x = calculate_x_nimbus(algorithm: algorithm, salt: salt, password: password)
    case .thinbus:
        x = calculate_x_thinbus(group: group, algorithm: algorithm, salt: salt, username: username, password: password)
    }
   
    return createSaltedVerificationKey(from: x, salt: salt, group: group)
}

/// Creates the salted verification key based on a precomputed SRP x value.
/// Only the salt and verification key need to be stored on the
/// server, there's no need to keep the plain-text password.
///
/// Keep the verification key private, as it can be used to brute-force
/// the password from.
///
/// - Parameters:
///   - x: precomputed SRP x
///   - salt: (optional) custom salt value; if providing a salt, make sure to
///       provide a good random salt of at least 16 bytes. Default is to
///       generate a salt of 16 bytes.
///   - group: `Group` parameters; default is 2048-bits group.
/// - Returns: salt (s) and verification key (v)
public func createSaltedVerificationKey(
    from x: Data,
    salt: Data? = nil,
    group: Group = .N2048)
    -> (salt: Data, verificationKey: Data)
{
    return createSaltedVerificationKey(from: BigUInt(x), salt: salt, group: group)
}

func createSaltedVerificationKey(
    from x: BigUInt,
    salt: Data? = nil,
    group: Group = .N2048)
    -> (salt: Data, verificationKey: Data)
{
    let salt = salt ?? randomBytes(16)
    let v = calculate_v(group: group, x: x)
    return (salt, v.serialize())
}

func pad(_ data: Data, to size: Int) -> Data {
    precondition(size >= data.count, "Negative padding not possible")
    return Data(count: size - data.count) + data
}

//u = H(PAD(A) | PAD(B))
func calculate_u(group: Group, algorithm: Digest.Algorithm, A: Data, B: Data) -> BigUInt {
    let H = Digest.hasher(algorithm)
    let size = group.N.serialize().count
    return BigUInt(H(pad(A, to: size) + pad(B, to: size)))
}

//u = H(A | B)
func calculate_u_thinbus(group: Group, algorithm: Digest.Algorithm, A: Data, B: Data) -> BigUInt {
    let H = Digest.hasher(algorithm)
    return BigUInt(H(A + B))
}

//M1 = H(H(N) XOR H(g) | H(I) | s | A | B | K)
func calculate_M(group: Group, algorithm: Digest.Algorithm, username: String, salt: Data, A: Data, B: Data, K: Data) -> Data {
    let H = Digest.hasher(algorithm)
    let HN_xor_Hg = (H(group.N.serialize()) ^ H(group.g.serialize()))!
    let HI = H(username.data(using: .utf8)!)
    return H(HN_xor_Hg + HI + salt + A + B + K)
}

//M1 = H(A | B | S)
func calculate_M_nimbus(group: Group, algorithm: Digest.Algorithm, A: Data, B: Data, S: Data) -> Data {
    let H = Digest.hasher(algorithm)
    return H(A + B + S)
}

//M1 = H(A | B | S)
func calculate_M_thinbus(group: Group, algorithm: Digest.Algorithm, A: Data, B: Data, S: Data) -> Data {
    let finalDigest = Digest(using: algorithm)
        .update(data: A)!
        .update(data: B)!
        .update(data: S)!
        .final()
    return Data(finalDigest)
}

//HAMK = H(A | M | K)
func calculate_HAMK(algorithm: Digest.Algorithm, A: Data, M: Data, K: Data) -> Data {
    let H = Digest.hasher(algorithm)
    return H(A + M + K)
}

//k = H(N | PAD(g))
func calculate_k(group: Group, algorithm: Digest.Algorithm) -> BigUInt {
    let H = Digest.hasher(algorithm)

    let size = group.N.serialize().count
    return BigUInt(H(group.N.serialize() + pad(group.g.serialize(), to: size)))
}

//x = H(s | H(I | ":" | P))
func calculate_x_thinbus(group: Group, algorithm: Digest.Algorithm, salt: Data, username: String, password: String) -> BigUInt {
    let H = Digest.hasher(algorithm)
    
    let saltHexStr = BigUInt(salt).serialize().hexEncodedString()
    
    let hash1 = H("\(username):\(password)".data(using: .utf8)!).normalize()

    let hash1HexStr = BigUInt(hash1).serialize().hexEncodedString()
            
    let hash = H("\(saltHexStr)\(hash1HexStr)".uppercased().data(using: .utf8)!).normalize()
    
    let resultNum = BigUInt(hash)
    
    return resultNum % group.N
}

//x = H(s | H(P))
func calculate_x_nimbus(algorithm: Digest.Algorithm, salt: Data, password: String) -> BigUInt {
    let H = Digest.hasher(algorithm)
    return BigUInt(H(salt + H(password.data(using: .utf8)!)).hexEncodedString(), radix: 16)!
}

// v = g^x % N
func calculate_v(group: Group, x: BigUInt) -> BigUInt {
    return group.g.power(x, modulus: group.N)
}

func randomBytes(_ count: Int) -> Data {
    return Data((0..<count).map { _ in UInt8.random(in: 0...255) })
}
