use futures_util::{SinkExt, StreamExt};
use tokio_tungstenite::connect_async;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let url = "ws://127.0.0.1:44321/ws";
    println!("Connecting to inconspicuous port {}", url);

    let (ws_stream, _) = connect_async(url).await?;
    println!("WebSocket connected successfully!");

    let (mut write, mut read) = ws_stream.split();

    // 1. Send prompt
    let prompt_msg = serde_json::json!({
        "type": "prompt",
        "payload": {
            "text": "Count: 1, 2, 3"
        }
    });

    println!("Sending prompt: {}", prompt_msg);
    write
        .send(tokio_tungstenite::tungstenite::Message::Text(prompt_msg.to_string().into()))
        .await?;

    let timeout = tokio::time::sleep(tokio::time::Duration::from_secs(12));
    tokio::pin!(timeout);

    let mut token_chunks_count = 0;

    loop {
        tokio::select! {
            msg = read.next() => {
                match msg {
                    Some(Ok(m)) => {
                        let text = m.to_string();
                        if text.contains("token_chunk") {
                            token_chunks_count += 1;
                            println!(">>> TOKEN CHUNK: {}", text);
                        } else {
                            println!("<<< MSG: {}", text);
                        }
                        if text.contains("turn_finished") {
                            println!("Turn finished! Total token chunks streamed: {}", token_chunks_count);
                            break;
                        }
                    }
                    Some(Err(e)) => {
                        eprintln!("Error: {:?}", e);
                        break;
                    }
                    None => break,
                }
            }
            _ = &mut timeout => {
                println!("Test timeout reached.");
                break;
            }
        }
    }

    Ok(())
}
