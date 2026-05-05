#!/usr/bin/env python3
"""
PanicGuardRF Retraining — Real WESAD Dataset
Delegates to train_rf_real.py which downloads and processes the real WESAD dataset.
Run with: python3 retrain_rf.py

Run this to retrain with real physiological data instead of synthetic distributions.
"""

if __name__ == "__main__":
    import sys, os
    # Add this directory to path and import the real pipeline
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from train_rf_real import main as _main
    _main()
