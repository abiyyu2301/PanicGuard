#!/usr/bin/env python3
"""Export PanicGuardRF.pkl → PanicGuardRF.mlpackage with named feature inputs."""
import os, sys, warnings
warnings.filterwarnings("ignore")

script_dir = os.path.dirname(os.path.abspath(__file__))
pkl_path = os.path.join(script_dir, "PanicGuardRF.pkl")
mlpkg_path = os.path.join(script_dir, "PanicGuardRF.mlpackage")

print("[1] Loading sklearn model...")
import joblib
rf = joblib.load(pkl_path)
print(f"    Loaded: {rf}")

print("[2] Converting to CoreML...")
import coremltools as ct

FEATURES = [
    "rmssd", "sdnn", "hr_mean", "hr_std",
    "lf_hf_ratio", "pnn50",
    "age_group", "time_of_day", "sleep_hours"
]

# Convert with named feature inputs and named outputs
# Note: sklearn converter maps these to MLMultiArray column indices
coreml_model = ct.converters.sklearn.convert(
    rf,
    input_features=FEATURES,
    output_feature_names=["panicProbability", "classLabel"]
)

# Annotate the model
coreml_model.author = "PanicGuard ML Pipeline"
coreml_model.license = "MIT"
coreml_model.short_description = (
    "PanicGuard panic disorder detection Random Forest. "
    "Input: 9 HRV+contextual features per 30s window. "
    "Output: panicProbability (Float 0-1), classLabel (predicted class index)."
)

# Print what we got
print("[3] Model interface:")
try:
    spec = coreml_model._spec
except AttributeError:
    spec = coreml_model.spec
for inp in spec.description.input:
    print(f"    INPUT  name={inp.name}  type={inp.type}")
for out in spec.description.output:
    print(f"    OUTPUT name={out.name}  type={out.type}")

print("[4] Saving to mlpackage...")
coreml_model.save(mlpkg_path)
print(f"[OK] Saved: {mlpkg_path}")
print("Done.")
