import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_trimmer/src/file_formats.dart';
import 'package:video_trimmer/src/storage_dir.dart';

enum TrimmerEvent { initialized }

class Trimmer {
  final StreamController<TrimmerEvent> _controller =
      StreamController<TrimmerEvent>.broadcast();
  VideoPlayerController? _videoPlayerController;
  VideoPlayerController? get videoPlayerController => _videoPlayerController;
  File? currentVideoFile;
  Stream<TrimmerEvent> get eventStream => _controller.stream;

  Future<void> loadVideo({required File videoFile}) async {
    currentVideoFile = videoFile;
    if (videoFile.existsSync()) {
      _videoPlayerController = VideoPlayerController.file(currentVideoFile!);
      await _videoPlayerController!.initialize().then((_) {
        _controller.add(TrimmerEvent.initialized);
      });
    }
  }

  Future<String> _createFolderInAppDocDir(
    String folderName,
    StorageDir? storageDir,
  ) async {
    Directory? _directory;
    if (storageDir == null) {
      _directory = await getApplicationDocumentsDirectory();
    } else {
      switch (storageDir.toString()) {
        case 'temporaryDirectory':
          _directory = await getTemporaryDirectory();
          break;
        case 'applicationDocumentsDirectory':
          _directory = await getApplicationDocumentsDirectory();
          break;
        case 'externalStorageDirectory':
          _directory = await getExternalStorageDirectory();
          break;
      }
    }
    // Directory + folder name
    final Directory _directoryFolder =
        Directory('${_directory!.path}/$folderName/');

    if (await _directoryFolder.exists()) {
      // If folder already exists return path
      return _directoryFolder.path;
    } else {
      // If folder does not exists create folder and then return its path
      final Directory _directoryNewFolder =
          await _directoryFolder.create(recursive: true);
      return _directoryNewFolder.path;
    }
  }

  Future<void> saveTrimmedVideo({
    required double startValue,
    required double endValue,
    required Function(String? outputPath) onSave,
    bool applyVideoEncoding = false,
    FileFormat? outputFormat,
    String? ffmpegCommand,
    String? customVideoFormat,
    int? fpsGIF,
    int? scaleGIF,
    String? videoFolderName,
    String? videoFileName,
    StorageDir? storageDir,
  }) async {
    final String _videoPath = currentVideoFile!.path;
    final String _videoName = basename(_videoPath).split('.')[0];
    String _command;
    // String _resultString;
    String _outputPath;
    String? _outputFormatString;
    videoFolderName ??= "Trimmer";
    videoFileName ??= "${_videoName}_trimmed:${DateTime.now()}";
    videoFileName = videoFileName.replaceAll(' ', '_');
    String path = await _createFolderInAppDocDir(
      videoFolderName,
      storageDir,
    ).whenComplete(
      () => debugPrint("Retrieved Trimmer folder"),
    );

    Duration startPoint = Duration(milliseconds: startValue.toInt());
    Duration endPoint = Duration(milliseconds: endValue.toInt());

    if (outputFormat == null) {
      outputFormat = FileFormat.mp4;
      _outputFormatString = outputFormat.toString();
    } else {
      _outputFormatString = outputFormat.toString();
    }

    String _trimLengthCommand =
        ' -ss $startPoint -i "$_videoPath" -t ${endPoint - startPoint} -avoid_negative_ts make_zero ';

    if (ffmpegCommand == null) {
      _command = '$_trimLengthCommand -c:a copy ';

      if (!applyVideoEncoding) {
        _command += '-c:v copy ';
      }

      if (outputFormat == FileFormat.gif) {
        fpsGIF ??= 10;
        scaleGIF ??= 480;
        _command =
            '$_trimLengthCommand -vf "fps=$fpsGIF,scale=$scaleGIF:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" -loop 0 ';
      }
    } else {
      _command = '$_trimLengthCommand $ffmpegCommand ';
      _outputFormatString = customVideoFormat;
    }

    _outputPath = '$path$videoFileName$_outputFormatString';

    _command += '"$_outputPath"';

    FFmpegKit.executeAsync(_command, (session) async {
      final state =
          FFmpegKitConfig.sessionStateToString(await session.getState());
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        onSave(_outputPath);
      } else {
        onSave(null);
      }
    });
  }

  Future<bool> videPlaybackControl({
    required double startValue,
    required double endValue,
  }) async {
    if (videoPlayerController!.value.isPlaying) {
      await videoPlayerController!.pause();
      return false;
    } else {
      if (videoPlayerController!.value.position.inMilliseconds >=
          endValue.toInt()) {
        await videoPlayerController!
            .seekTo(Duration(milliseconds: startValue.toInt()));
        await videoPlayerController!.play();
        return true;
      } else {
        await videoPlayerController!.play();
        return true;
      }
    }
  }

  void dispose() {
    _controller.close();
  }
}
