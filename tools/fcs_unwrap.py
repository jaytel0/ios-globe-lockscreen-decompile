#!/usr/bin/env python3
"""Recover the AEA main key from Apple's published FCS key.

The AEA header carries {enc-request, wrapped-key}. enc-request is an ephemeral
X9.63 P-256 public key; ECDH it against the published private key, run the
ANSI X9.63 KDF to get a KEK, then RFC 3394 unwrap the wrapped key. RFC 3394
carries its own integrity check, so a successful unwrap confirms the derivation.
"""
import base64, hashlib, json, re, sys
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import load_pem_private_key
from cryptography.hazmat.primitives.keywrap import aes_key_unwrap, InvalidUnwrap

head = open(sys.argv[1], "rb").read()
m = re.search(rb'\{"enc-request".*?\}', head, re.S)
fcs = json.loads(m.group(0))
enc_request = base64.b64decode(fcs["enc-request"])
wrapped_key = base64.b64decode(fcs["wrapped-key"])
print(f"enc-request : {len(enc_request)} bytes  (X9.63 pubkey)")
print(f"wrapped-key : {len(wrapped_key)} bytes")

priv = load_pem_private_key(open(sys.argv[2], "rb").read(), password=None)
pub = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), enc_request)
shared = priv.exchange(ec.ECDH(), pub)
print(f"shared secret: {shared.hex()}")

own_pub = priv.public_key().public_bytes(
    __import__("cryptography").hazmat.primitives.serialization.Encoding.X962,
    __import__("cryptography").hazmat.primitives.serialization.PublicFormat.UncompressedPoint)

def x963(z, info, length=32):
    out, ctr = b"", 1
    while len(out) < length:
        out += hashlib.sha256(z + ctr.to_bytes(4, "big") + info).digest()
        ctr += 1
    return out[:length]

candidates = {
    "sharedinfo=enc-request": enc_request,
    "sharedinfo=empty": b"",
    "sharedinfo=ephemeral||recipient": enc_request + own_pub,
}
for name, info in candidates.items():
    kek = x963(shared, info)
    try:
        key = aes_key_unwrap(kek, wrapped_key)
    except InvalidUnwrap:
        print(f"  {name}: integrity check failed")
        continue
    print(f"\nSUCCESS via {name}")
    print(f"AEA main key ({len(key)} bytes): {key.hex()}")
    open("main_key.b64", "w").write(base64.b64encode(key).decode())
    break
