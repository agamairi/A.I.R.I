# A.I.R.I - Artificial Intelligence, Real-Time, In-App

A.I.R.I is a privacy-focused, high-performance mobile application designed to run large language models locally on your smartphone. Built with Flutter and optimized for on-device inference, A.I.R.I ensures your data never leaves your device while providing a sophisticated AI companion experience.

## Features

### Local Inference and Model Management

- Direct model downloads from Hugging Face with granular quantization selection.
- Local model importing and offloading to manage device storage and memory.
- Screen wake lock support during long-running model operations.

### Sophisticated Conversational Interfaces
- **Multimodal Chat**: A modern chat experience supporting text, images, and PDF documents.
- **Seamless Talk**: A hands-free voice interface with a dynamic orb visualization, featuring synchronized speech-to-text and text-to-speech.
- **Persistent Sessions**: Automated saving of chat and talk sessions with full context restoration.

### Advanced Capabilities
- **On-Device RAG (Retrieval-Augmented Generation)**: Ingest local PDF documents to ground AI responses in your own data.
- **Vision Integration**: Capture and analyze visual data using the device camera for real-time AI insights.
- **LAN Server Mode**: Host your local model as an Ollama-compatible API endpoint over your local network.

### Customization and Performance
- Dynamic Material 3 design system with customizable primary colors.
- High-performance dark and light mode support.
- Optimized resource management with dedicated background services for model handling.

## Architecture

The project follows a feature-first architectural pattern to ensure scalability and maintainability:

- **features/**: Discrete modules for Chat, Vision, Speech, Notebook (RAG), and Model Management.
- **services/**: specialized handlers for local database operations, background processing, and network communications.
- **viewmodels/**: State management implementation using the Provider pattern.

## Getting Started

### Prerequisites
- Flutter SDK (v3.10.7 or later)
- Dart SDK
- Android or iOS physical device (Recommended for local inference performance)

### Installation
1.  **Clone the Repository**:
    ```bash
    git clone https://github.com/agamairi/A.I.R.I.git
    ```
2.  **Install Dependencies**:
    ```bash
    flutter pub get
    ```
3.  **Run the Application**:
    ```bash
    flutter run
    ```

## Usage
- **Download Models**: Use the Model Manager to browse Hugging Face and select specific quantizations for download.
- **Notebook**: Add PDF files to your local notebook to enable grounded inference.
- **LAN Access**: Enable the LAN Server in settings to access your mobile-hosted model from other devices.

## License
This project is licensed under the MIT License.
