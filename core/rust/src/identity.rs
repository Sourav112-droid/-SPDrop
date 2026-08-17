use anyhow::{ensure, Result};
use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};
use hkdf::Hkdf;
use rand::rngs::OsRng;
use rand::RngCore;
use sha2::{Digest, Sha256};
use x25519_dalek::{PublicKey, StaticSecret};

pub const PROTOCOL_VERSION: u16 = 1;

pub fn generate_static_keypair() -> Vec<u8> {
    let mut csprng = OsRng;
    let signing_key = SigningKey::generate(&mut csprng);
    signing_key.to_bytes().to_vec()
}

pub fn get_public_key(private_key: &[u8]) -> Result<Vec<u8>> {
    let signing_key = SigningKey::from_bytes(private_key.try_into()?);
    Ok(signing_key.verifying_key().to_bytes().to_vec())
}

pub struct Msg1Payload {
    pub ephemeral_pub: [u8; 32],
    pub static_pub: [u8; 32],
    pub nonce: [u8; 32],
}

impl Msg1Payload {
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(96);
        buf.extend_from_slice(&self.ephemeral_pub);
        buf.extend_from_slice(&self.static_pub);
        buf.extend_from_slice(&self.nonce);
        buf
    }
    pub fn from_bytes(bytes: &[u8]) -> Result<Self> {
        ensure!(bytes.len() == 96, "Invalid Msg1 length");
        Ok(Self {
            ephemeral_pub: bytes[0..32].try_into().unwrap(),
            static_pub: bytes[32..64].try_into().unwrap(),
            nonce: bytes[64..96].try_into().unwrap(),
        })
    }
}

pub struct Msg2Payload {
    pub ephemeral_pub: [u8; 32],
    pub static_pub: [u8; 32],
    pub nonce: [u8; 32],
    pub signature: [u8; 64],
}

impl Msg2Payload {
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(160);
        buf.extend_from_slice(&self.ephemeral_pub);
        buf.extend_from_slice(&self.static_pub);
        buf.extend_from_slice(&self.nonce);
        buf.extend_from_slice(&self.signature);
        buf
    }
    pub fn from_bytes(bytes: &[u8]) -> Result<Self> {
        ensure!(bytes.len() == 160, "Invalid Msg2 length");
        Ok(Self {
            ephemeral_pub: bytes[0..32].try_into().unwrap(),
            static_pub: bytes[32..64].try_into().unwrap(),
            nonce: bytes[64..96].try_into().unwrap(),
            signature: bytes[96..160].try_into().unwrap(),
        })
    }
}

pub struct Msg3Payload {
    pub signature: [u8; 64],
}
impl Msg3Payload {
    pub fn to_bytes(&self) -> Vec<u8> {
        self.signature.to_vec()
    }
    pub fn from_bytes(bytes: &[u8]) -> Result<Self> {
        ensure!(bytes.len() == 64, "Invalid Msg3 length");
        Ok(Self {
            signature: bytes[0..64].try_into().unwrap(),
        })
    }
}

// Canonical Transcript Hash Binding
fn hash_transcript(
    msg1_ephemeral: &[u8; 32],
    msg1_static: &[u8; 32],
    msg1_nonce: &[u8; 32],
    msg2_ephemeral: Option<&[u8; 32]>,
    msg2_static: Option<&[u8; 32]>,
    msg2_nonce: Option<&[u8; 32]>,
) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(b"SP_DROP_AKE");
    hasher.update(&PROTOCOL_VERSION.to_be_bytes());
    
    // Initiator inputs
    hasher.update(b"INITIATOR_EPH");
    hasher.update(msg1_ephemeral);
    hasher.update(b"INITIATOR_STA");
    hasher.update(msg1_static);
    hasher.update(b"INITIATOR_NON");
    hasher.update(msg1_nonce);
    
    // Responder inputs
    if let Some(eph) = msg2_ephemeral {
        hasher.update(b"RESPONDER_EPH");
        hasher.update(eph);
        hasher.update(b"RESPONDER_STA");
        hasher.update(msg2_static.unwrap());
        hasher.update(b"RESPONDER_NON");
        hasher.update(msg2_nonce.unwrap());
    }
    
    hasher.finalize().into()
}

fn derive_keys(salt: &[u8], shared_secret: &[u8]) -> (Vec<u8>, Vec<u8>, String) {
    let hk = Hkdf::<Sha256>::new(Some(salt), shared_secret);
    
    // Directionally separated keys
    let mut initiator_tx = [0u8; 32];
    hk.expand(b"SPDROP_INITIATOR_TX", &mut initiator_tx).unwrap();
    
    let mut responder_tx = [0u8; 32];
    hk.expand(b"SPDROP_RESPONDER_TX", &mut responder_tx).unwrap();

    // SAS material separated from session keys
    let mut sas_okm = [0u8; 4];
    hk.expand(b"SPDROP_SAS", &mut sas_okm).unwrap();
    let sas_num = u32::from_be_bytes(sas_okm) % 1_000_000;
    let sas = format!("{:03}-{:03}", sas_num / 1000, sas_num % 1000);

    (initiator_tx.to_vec(), responder_tx.to_vec(), sas)
}

pub struct InitiatorStartResult {
    pub msg1_bytes: Vec<u8>,
    pub ephemeral_secret: Vec<u8>,
    pub initiator_nonce: Vec<u8>,
}

pub fn handshake_initiator_start(private_key: &[u8]) -> Result<InitiatorStartResult> {
    let signing_key = SigningKey::from_bytes(private_key.try_into()?);
    
    let ephemeral_secret = StaticSecret::random_from_rng(OsRng);
    let ephemeral_pub = PublicKey::from(&ephemeral_secret);
    
    let mut nonce = [0u8; 32];
    OsRng.fill_bytes(&mut nonce);

    let msg1 = Msg1Payload {
        ephemeral_pub: *ephemeral_pub.as_bytes(),
        static_pub: signing_key.verifying_key().to_bytes(),
        nonce,
    };

    Ok(InitiatorStartResult {
        msg1_bytes: msg1.to_bytes(),
        ephemeral_secret: ephemeral_secret.to_bytes().to_vec(),
        initiator_nonce: nonce.to_vec(),
    })
}

pub struct ResponderStartResult {
    pub msg2_bytes: Vec<u8>,
    pub peer_static_pub: Vec<u8>,
    pub expected_msg3_hash: Vec<u8>,
    pub sas: String,
    pub session_key_rx: Vec<u8>,
    pub session_key_tx: Vec<u8>,
}

pub fn handshake_responder_start(
    private_key: &[u8],
    msg1_bytes: &[u8],
) -> Result<ResponderStartResult> {
    let msg1 = Msg1Payload::from_bytes(msg1_bytes)?;
    let peer_static_pub = VerifyingKey::from_bytes(&msg1.static_pub)?;

    let signing_key = SigningKey::from_bytes(private_key.try_into()?);
    let ephemeral_secret = StaticSecret::random_from_rng(OsRng);
    let ephemeral_pub = PublicKey::from(&ephemeral_secret);
    
    let mut nonce = [0u8; 32];
    OsRng.fill_bytes(&mut nonce);

    // Signature binds to the full unauthenticated transcript so far
    let sig_input = hash_transcript(
        &msg1.ephemeral_pub,
        &msg1.static_pub,
        &msg1.nonce,
        Some(ephemeral_pub.as_bytes()),
        Some(signing_key.verifying_key().as_bytes()),
        Some(&nonce),
    );
    let signature = signing_key.sign(&sig_input);

    let msg2 = Msg2Payload {
        ephemeral_pub: *ephemeral_pub.as_bytes(),
        static_pub: signing_key.verifying_key().to_bytes(),
        nonce,
        signature: signature.to_bytes(),
    };

    let peer_ephemeral = PublicKey::from(msg1.ephemeral_pub);
    let shared_secret = ephemeral_secret.diffie_hellman(&peer_ephemeral);

    // For Responder, session salt is the exact same full transcript hash
    let salt = sig_input;
    let (initiator_tx, responder_tx, sas) = derive_keys(&salt, shared_secret.as_bytes());

    Ok(ResponderStartResult {
        msg2_bytes: msg2.to_bytes(),
        peer_static_pub: peer_static_pub.to_bytes().to_vec(),
        expected_msg3_hash: salt.to_vec(),
        sas,
        session_key_rx: initiator_tx,
        session_key_tx: responder_tx,
    })
}

pub fn handshake_responder_finish(
    peer_static_pub_bytes: &[u8],
    expected_msg3_hash: &[u8],
    msg3_bytes: &[u8],
) -> Result<()> {
    let peer_static_pub = VerifyingKey::from_bytes(peer_static_pub_bytes.try_into()?)?;
    let msg3 = Msg3Payload::from_bytes(msg3_bytes)?;
    let signature = Signature::from_bytes(&msg3.signature);

    peer_static_pub.verify(expected_msg3_hash, &signature)?;
    Ok(())
}

pub struct InitiatorFinishResult {
    pub msg3_bytes: Vec<u8>,
    pub peer_static_pub: Vec<u8>,
    pub sas: String,
    pub session_key_rx: Vec<u8>,
    pub session_key_tx: Vec<u8>,
}

pub fn handshake_initiator_finish(
    private_key: &[u8],
    ephemeral_secret_bytes: &[u8],
    msg1_bytes: &[u8],
    msg2_bytes: &[u8],
) -> Result<InitiatorFinishResult> {
    let signing_key = SigningKey::from_bytes(private_key.try_into()?);
    let msg1 = Msg1Payload::from_bytes(msg1_bytes)?;
    let msg2 = Msg2Payload::from_bytes(msg2_bytes)?;
    
    let peer_static_pub = VerifyingKey::from_bytes(&msg2.static_pub)?;
    let peer_signature = Signature::from_bytes(&msg2.signature);

    // Verify Responder's Signature
    let sig_input = hash_transcript(
        &msg1.ephemeral_pub,
        &msg1.static_pub,
        &msg1.nonce,
        Some(&msg2.ephemeral_pub),
        Some(&msg2.static_pub),
        Some(&msg2.nonce),
    );
    
    peer_static_pub.verify(&sig_input, &peer_signature)?;

    // Initiator signs the exact same transcript to prove they have the private key 
    // corresponding to the static_pub they claimed in Msg1
    let signature = signing_key.sign(&sig_input);

    let msg3 = Msg3Payload {
        signature: signature.to_bytes(),
    };

    let ephemeral_secret = StaticSecret::from(<[u8; 32]>::try_from(ephemeral_secret_bytes).unwrap());
    let peer_ephemeral = PublicKey::from(msg2.ephemeral_pub);
    let shared_secret = ephemeral_secret.diffie_hellman(&peer_ephemeral);

    let (initiator_tx, responder_tx, sas) = derive_keys(&sig_input, shared_secret.as_bytes());

    Ok(InitiatorFinishResult {
        msg3_bytes: msg3.to_bytes(),
        peer_static_pub: peer_static_pub.to_bytes().to_vec(),
        sas,
        session_key_tx: initiator_tx,
        session_key_rx: responder_tx,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_handshake_success() {
        let init_priv = generate_static_keypair();
        let resp_priv = generate_static_keypair();

        let init_start = handshake_initiator_start(&init_priv).unwrap();
        let resp_start = handshake_responder_start(&resp_priv, &init_start.msg1_bytes).unwrap();
        let init_finish = handshake_initiator_finish(&init_priv, &init_start.ephemeral_secret, &init_start.msg1_bytes, &resp_start.msg2_bytes).unwrap();
        handshake_responder_finish(&resp_start.peer_static_pub, &resp_start.expected_msg3_hash, &init_finish.msg3_bytes).unwrap();

        assert_eq!(init_finish.session_key_tx, resp_start.session_key_rx);
        assert_eq!(init_finish.session_key_rx, resp_start.session_key_tx);
        assert_eq!(init_finish.sas, resp_start.sas);
        assert_ne!(init_finish.session_key_tx, init_finish.session_key_rx);
    }

    #[test]
    fn test_handshake_tampered_msg1() {
        let init_priv = generate_static_keypair();
        let resp_priv = generate_static_keypair();

        let init_start = handshake_initiator_start(&init_priv).unwrap();
        // Tamper with ephemeral pub in msg1 sent to responder
        let mut tampered_msg1 = init_start.msg1_bytes.clone();
        tampered_msg1[0] ^= 1;
        
        let resp_start = handshake_responder_start(&resp_priv, &tampered_msg1).unwrap();
        
        let init_finish = handshake_initiator_finish(&init_priv, &init_start.ephemeral_secret, &init_start.msg1_bytes, &resp_start.msg2_bytes);
        assert!(init_finish.is_err());
    }

    #[test]
    fn test_handshake_tampered_msg2() {
        let init_priv = generate_static_keypair();
        let resp_priv = generate_static_keypair();

        let init_start = handshake_initiator_start(&init_priv).unwrap();
        let mut resp_start = handshake_responder_start(&resp_priv, &init_start.msg1_bytes).unwrap();
        // Tamper with nonce in msg2
        resp_start.msg2_bytes[65] ^= 1;

        let init_finish = handshake_initiator_finish(&init_priv, &init_start.ephemeral_secret, &init_start.msg1_bytes, &resp_start.msg2_bytes);
        assert!(init_finish.is_err()); // Signature verification fails
    }

    #[test]
    fn test_handshake_replay() {
        let init_priv = generate_static_keypair();
        let resp_priv = generate_static_keypair();

        let init_start = handshake_initiator_start(&init_priv).unwrap();
        let resp_start1 = handshake_responder_start(&resp_priv, &init_start.msg1_bytes).unwrap();
        
        // MITM replays msg1
        let resp_start2 = handshake_responder_start(&resp_priv, &init_start.msg1_bytes).unwrap();
        
        assert_ne!(resp_start1.msg2_bytes, resp_start2.msg2_bytes);
        assert_ne!(resp_start1.session_key_tx, resp_start2.session_key_tx);
        
        // Ensure new fresh SAS and keys are generated per replay instance
        assert_ne!(resp_start1.sas, resp_start2.sas);
    }
}
