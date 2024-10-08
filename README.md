# NarrateIt

NarrateIt is a macOS application that allows users to extract text from PDF documents and images, and then synthesize speech from the extracted text using ElevenLabs' text-to-speech API. It also features voice cloning capabilities for personalized text-to-speech experiences.

- **Read in Your Own Voice**: With NarrateIt's voice cloning feature, users can create a digital version of their own voice and use it to read any document, providing a truly personalized text-to-speech experience.

## Highlights

- **AI-Developed Application**: This application was developed entirely using AI assistance, specifically [Claude-3.5 Sonnet](https://claude.ai) (an AI language model) and [Cursor](https://cursor.sh) (an AI-powered code editor), without any manual code writing.


## Features

- Extract text from PDF documents and images
- Synthesize speech from extracted text using ElevenLabs API
- Voice cloning for personalized text-to-speech
- Customizable voice settings
- Word count display
- Audio playback controls
- Dark mode support

## Requirements

- macOS 11.0 or later
- Xcode 12.0 or later
- Swift 5.3 or later
- An ElevenLabs API key

## Setup

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/NarrateIt.git
   ```

2. Open the project in Xcode:
   ```
   cd NarrateIt
   open NarrateIt.xcodeproj
   ```

3. In the `Environment.swift` file, replace the placeholder API key with your actual ElevenLabs API key:
   ```swift
   static let elevenLabsAPIKey: String = "YOUR_API_KEY_HERE"
   ```

4. Build and run the project in Xcode.

## Usage

1. Launch the NarrateIt application.
2. Drag and drop a PDF or image file onto the application window, or click to select a file.
3. The application will extract text from the document.
4. Click the play button to synthesize speech from the extracted text.
5. Use the playback controls to pause, resume, or stop the audio playback.

## Voice Cloning

NarrateIt supports voice cloning, allowing you to create personalized text-to-speech voices:

1. Go to Settings by clicking the gear icon in the top-right corner.
2. In the Voice Settings section, click "Clone New Voice".
3. Enter a name for your cloned voice.
4. Read the provided text snippet when prompted to record your voice.
5. Click "Clone Voice" to send the recording to ElevenLabs for processing.
6. Once cloned, your new voice will appear in the list of available voices.
7. Select your cloned voice as the default voice for text-to-speech synthesis.

## Configuration

You can customize the following settings in the application:

- Font size
- Line spacing
- App theme (light/dark/system)
- Default voice for text-to-speech

Access these settings by clicking the gear icon in the top-right corner of the application window.

## Contributing

Contributions to NarrateIt are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [ElevenLabs](https://elevenlabs.io/) for providing the text-to-speech and voice cloning API
- [SwiftUI](https://developer.apple.com/xcode/swiftui/) for the user interface framework
- [Vision](https://developer.apple.com/documentation/vision) for OCR capabilities

## Support

If you encounter any issues or have questions, please file an issue on the GitHub repository.