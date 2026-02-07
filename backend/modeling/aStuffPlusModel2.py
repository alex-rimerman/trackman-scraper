class aStuffPlusModel:
    def __init__(self):
        self.model = None
        self.feature_importance = None
        self.best_params = None
        self.fastball_stats_cache = None

        self.numeric_features = [
            'release_speed',
            'pfx_z',
            'adj_hmov',
            'release_spin_rate',
            'adj_spin_axis',
            'release_extension',
            'release_pos_z',
            'adj_release_x',
            'velo_diff',
            'ivb_diff',
            'hmov_diff'
        ]

        self.categorical_features = ['pitch_type']

        self.scalers = {}
        self.global_scaler = None
        self.min_stuff = 40
        self.max_stuff = 160

    def load_model(self, path: str):
        import xgboost as xgb
        self.model = xgb.XGBRegressor()
        self.model.load_model(path)
        print(f"Model loaded from {path}")
        return self.model

    def save_model(self, path: str):
        if self.model is None:
            raise ValueError("Model must be trained before saving")
        self.model.save_model(path)
        print(f"Model saved to {path}")

    def predict_stuff_plus(self, X):
        import numpy as np
        if self.model is None:
            raise ValueError("Model must be trained before making predictions")

        missing = [c for c in self.numeric_features if c not in X.columns]
        if missing:
            raise ValueError(f"Missing numeric features for prediction: {missing}")

        preds = self.model.predict(X[self.numeric_features])
        stuff_vals = []

        for pitch_type, raw_pred in zip(X['pitch_type'], preds):
            scaler = self.scalers.get(pitch_type, self.global_scaler)
            scaled = (raw_pred - scaler.mean_[0]) / scaler.scale_[0]
            sp = 100.0 + (scaled * 10.0)
            sp = float(np.clip(sp, self.min_stuff, self.max_stuff))
            stuff_vals.append(sp)

        return np.array(stuff_vals)

    def predict_single_pitch(
        self,
        pitch_type,
        release_speed,
        pfx_x,
        pfx_z,
        release_extension,
        release_spin_rate,
        spin_axis,
        release_pos_x,
        release_pos_z,
        p_throws,
        fb_velo,
        fb_ivb,
        fb_hmov
    ):
        import numpy as np
        if self.model is None:
            raise ValueError("Model must be trained before making predictions")

        velo_diff = release_speed - fb_velo
        ivb_diff = pfx_z - fb_ivb
        hmov_diff = pfx_x - fb_hmov
        adj_hmov = -pfx_x if p_throws == 'L' else pfx_x
        adj_release_x = -release_pos_x if p_throws == 'L' else release_pos_x
        adj_spin_axis = 360 - spin_axis if p_throws == 'L' else spin_axis

        feature_map = {
            'release_speed': float(release_speed),
            'pfx_z': float(pfx_z),
            'adj_hmov': float(adj_hmov),
            'release_spin_rate': float(release_spin_rate),
            'adj_spin_axis': float(adj_spin_axis),
            'release_extension': float(release_extension),
            'release_pos_z': float(release_pos_z),
            'adj_release_x': float(adj_release_x),
            'velo_diff': float(velo_diff),
            'ivb_diff': float(ivb_diff),
            'hmov_diff': float(hmov_diff)
        }

        X_input = np.array([feature_map[f] for f in self.numeric_features], dtype=float).reshape(1, -1)
        raw_pred = self.model.predict(X_input)[0]

        scaler = self.scalers.get(pitch_type, self.global_scaler)
        scaled = (raw_pred - scaler.mean_[0]) / scaler.scale_[0]
        stuff_plus = 100.0 + (scaled * 10.0)
        return float(np.clip(stuff_plus, self.min_stuff, self.max_stuff))
