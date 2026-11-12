# StandardLibrary 規約

Trident の外でも使える標準部品。ここのスクリプトが正で、Trident のネイティブ実装(将来)はその高速な置換にすぎない。

## 構成

- `StandardLibrary/<用途>/<ファイル>.js`。深さは 2 まで。増えたら用途フォルダの中で分ける。
- 種別はフォルダに入れない。ヘッダの `laser` 入力で決まる(なし = Generator、あり = Effect、`laser` 入力は 1 つまで)。
- 1 ファイル 1 アセット。`.ls` は Trident が未対応なので使わない。
- 現状の `Animations` / `Effects` は種別で分かれている。用途フォルダへ移す(未着手)。

## ヘッダ

必須: `LASERSCRIPT`, `NAME`, `DESCRIPTION`, `ID`, `VERSION`, `CATEGORIES`(用途フォルダ名の 1 つ), `TAGS`。

- `ID` は `xlaser.std.rotate` の形。フォルダを移しても変えない。
- 入力ごとに `NAME`, `TYPE`, `LABEL`。数値は `DEFAULT`, `MIN`, `MAX`, `UNIT` も付ける。

## 座標と単位

- 原点中心で、-1〜1 の単位立方体に収める。既定値のままで見えること。
- 大きさ: 丸い形は `radius`(半径)、線のように半径がない形は `length`(全長)。
- 角度の入力は度。
- 色は `color`(RGBA、既定は白)。
- Effect は blank 頂点の色を変えない。`source` が未接続なら何も出さずに return する。

## 時間

- 使ってよいのは `context.time` だけ。`Date` と `Math.random` は使わない(結果を再現できるように)。
- 動きの速さは `speed`(1 秒あたりの周期数)。位相は積算して、速度を変えてもジャンプしないようにする。積算は状態を持つので、`TAGS` に `stateful` を付ける。

## 書き方

- 頂点を作るループは `reserveVertices` + `commitVertices` か `addVertices`。`addVertex` のループは避ける(測定で約 4 倍遅い)。
- Effect は `addStream` してから `output.values` を直接書き換える(`Rotate.js` と `Colorize.js` が見本)。

## 追加するときの確認

1. `XLaserPreview` で描画を見る(3D なら視点を変えて)。
2. レポートに、空の出力、非有限値、立方体外の頂点が出ていないこと。
3. `swift test` が通ること。全アセットを検査するテストは未作成。

## 既存の例外

- `RotatingLine` の `speed` はラジアン/秒。周期/秒に揃える。
- 4 本とも `DESCRIPTION` `ID` `VERSION` `CATEGORIES` `TAGS` `LABEL` が未記入。
