use futures_util::{SinkExt, StreamExt};
use tokio_tungstenite::connect_async;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let url = "ws://127.0.0.1:8089/ws";
    println!("Connecting to {}", url);

    let (ws_stream, _) = connect_async(url).await?;
    println!("WebSocket connected successfully!");

    let (mut write, mut read) = ws_stream.split();

    // Send prompt
    let prompt_msg = serde_json::json!({
        "type": "prompt",
        "payload": {
            "text": "echo CodePill Dynamic Island Test"
        }
    });

    println!("Sending prompt: {}", prompt_msg);
    write
        .send(tokio_tungstenite::tungstenite::Message::Text(prompt_msg.to_string().into()))
        .await?;

    // Read responses for up to 10 seconds
    let timeout = tokio::time::sleep(tokio::time::Duration::from_secs(10));
    tokio::pin!(timeout);

    loop {
        tokio::select! {
            msg = read.next() => {
                match msg {
                    Some(Ok(m)) => {
                        println!("<<< RECEIVED: {}", m);
                        if m.to_string().contains("turn_finished") {
                            println!("Turn finished received!");
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
