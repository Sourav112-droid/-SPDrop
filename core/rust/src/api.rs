use anyhow::Result;
use flutter_rust_bridge::frb;
pub use crate::identity::{
    InitiatorStartResult,
    ResponderStartResult,
    InitiatorFinishResult,
};

pub fn api_handshake_initiator_start(private_key: Vec<u8>) -> Result<InitiatorStartResult> {
    crate::identity::handshake_initiator_start(&private_key)
}

pub fn api_handshake_responder_start(
    private_key: Vec<u8>,
    msg1_bytes: Vec<u8>,
) -> Result<ResponderStartResult> {
    crate::identity::handshake_responder_start(&private_key, &msg1_bytes)
}

pub fn api_handshake_initiator_finish(
    private_key: Vec<u8>,
    ephemeral_secret_bytes: Vec<u8>,
    msg1_bytes: Vec<u8>,
    msg2_bytes: Vec<u8>,
) -> Result<InitiatorFinishResult> {
    crate::identity::handshake_initiator_finish(&private_key, &ephemeral_secret_bytes, &msg1_bytes, &msg2_bytes)
}

pub fn api_handshake_responder_finish(
    peer_static_pub_bytes: Vec<u8>,
    expected_msg3_hash: Vec<u8>,
    msg3_bytes: Vec<u8>,
) -> Result<()> {
    crate::identity::handshake_responder_finish(&peer_static_pub_bytes, &expected_msg3_hash, &msg3_bytes)
}

pub fn api_generate_static_keypair() -> Vec<u8> {
    crate::identity::generate_static_keypair()
}

pub fn api_get_public_key(private_key: Vec<u8>) -> Result<Vec<u8>> {
    crate::identity::get_public_key(&private_key)
}


