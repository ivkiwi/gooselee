#!/usr/bin/env python3
"""Export the GigaAM v4 RNNT artifacts that ONNXGigaAMV4ModelStore downloads.

Usage: python3 export_gigaam_v4_onnx.py GIGAAM_CHECKOUT OUTPUT_DIR
Needs the GigaAM requirements plus torch, torchaudio and onnxscript.
Upload the printed files to the release named in ONNXGigaAMV4ModelStore and copy the hashes there.
"""
import hashlib
import sys
from pathlib import Path

checkout, output = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, str(checkout))

import gigaam  # noqa: E402
import onnx  # noqa: E402
import sentencepiece  # noqa: E402
import torch  # noqa: E402
from gigaam.preprocess import FeatureExtractor  # noqa: E402
from onnxruntime.quantization import QuantType, quantize_dynamic  # noqa: E402

work = output / "fp32"
model = gigaam.load_model("v4_rnnt", fp16_encoder=False, device="cpu", download_root=str(output / "ckpt"))
model.to_onnx(str(work))  # v4_rnnt_encoder.onnx (both heads' joint projections) + v4_rnnt_advance.onnx

# Per-channel QUInt8 keeps punctuation close to FP32; QInt8 ConvInteger has no CPU kernel.
quantize_dynamic(
    str(work / "v4_rnnt_encoder.onnx"),
    str(output / "v4_rnnt_encoder.int8.onnx"),
    weight_type=QuantType.QUInt8,
    per_channel=True,
)
(output / "v4_rnnt_advance.onnx").write_bytes((work / "v4_rnnt_advance.onnx").read_bytes())


class Preprocessor(torch.nn.Module):
    def __init__(self, cfg):
        super().__init__()
        self.features = FeatureExtractor(**{k: v for k, v in cfg.items() if k != "_target_"})

    def forward(self, waveforms, waveforms_lens):
        return self.features(waveforms, waveforms_lens)


# The dynamo exporter keeps a real STFT; the helper feeds waveforms/waveforms_lens and reads features/features_lens.
preprocessor_path = work / "gigaam_v4_preprocessor.onnx"
torch.onnx.export(
    Preprocessor(dict(model.cfg.preprocessor)).eval(),
    (torch.randn(2, 32000), torch.tensor([32000, 20000])),
    str(preprocessor_path),
    input_names=["waveforms", "waveforms_lens"],
    output_names=["features", "features_lens"],
    dynamic_axes={
        "waveforms": {0: "b", 1: "n"},
        "waveforms_lens": {0: "b"},
        "features": {0: "b", 2: "t"},
        "features_lens": {0: "b"},
    },
    opset_version=18,
    dynamo=True,
)
onnx.save(onnx.load(str(preprocessor_path)), str(output / "gigaam_v4_preprocessor.onnx"), save_as_external_data=False)

# The e2e head is index 0 of the advance output; its SentencePiece pieces plus the blank id.
tokenizer = sentencepiece.SentencePieceProcessor(model_file=str(work / "v4_rnnt_e2e_tokenizer.model"))
pieces = [tokenizer.id_to_piece(i) for i in range(tokenizer.get_piece_size())]
lines = [f"{piece} {index}\n" for index, piece in enumerate(pieces)] + [f"<blk> {len(pieces)}\n"]
(output / "v4_rnnt_e2e_vocab.txt").write_text("".join(lines), encoding="utf-8")

for name in ["v4_rnnt_encoder.int8.onnx", "v4_rnnt_advance.onnx", "gigaam_v4_preprocessor.onnx", "v4_rnnt_e2e_vocab.txt"]:
    data = (output / name).read_bytes()
    print(name, len(data), hashlib.sha256(data).hexdigest())
