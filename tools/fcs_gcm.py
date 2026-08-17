#!/usr/bin/env python3
"""wrapped-key is 48 bytes = 32 ciphertext + 16 GCM tag -> Apple ECIES AES-GCM.
Search the plausible X9.63-KDF / nonce variants; the GCM tag authenticates,
so exactly one combination can succeed."""
import base64, hashlib, json, re, sys, itertools
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import (
    load_pem_private_key, Encoding, PublicFormat)
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

head = open(sys.argv[1], "rb").read()
fcs = json.loads(re.search(rb'\{"enc-request".*?\}', head, re.S).group(0))
enc_request = base64.b64decode(fcs["enc-request"])
wrapped = base64.b64decode(fcs["wrapped-key"])

priv = load_pem_private_key(open(sys.argv[2], "rb").read(), password=None)
pub = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), enc_request)
z = priv.exchange(ec.ECDH(), pub)
own_pub = priv.public_key().public_bytes(Encoding.X962, PublicFormat.UncompressedPoint)

def x963(zz, info, n):
    out, ctr = b"", 1
    while len(out) < n:
        out += hashlib.sha256(zz + ctr.to_bytes(4, "big") + info).digest()
        ctr += 1
    return out[:n]

infos = {"encreq": enc_request, "empty": b"", "eph+recip": enc_request + own_pub}
aads  = {"none": b"", "encreq": enc_request}

for iname, info in infos.items():
    for klen, nmode in itertools.product((16, 32), ("zero12", "zero16", "kdf12", "kdf16")):
        if nmode.startswith("zero"):
            nlen = int(nmode[4:]); material = x963(z, info, klen)
            key, nonce = material, b"\x00" * nlen
        else:
            nlen = int(nmode[3:]); material = x963(z, info, klen + nlen)
            key, nonce = material[:klen], material[klen:]
        for aname, aad in aads.items():
            try:
                out = AESGCM(key).decrypt(nonce, wrapped, aad)
            except Exception:
                continue
            print(f"SUCCESS  info={iname} keylen={klen} nonce={nmode} aad={aname}")
            print(f"AEA main key ({len(out)} bytes): {out.hex()}")
            open("main_key.b64", "w").write(base64.b64encode(out).decode())
            sys.exit(0)
print("no variant matched")
