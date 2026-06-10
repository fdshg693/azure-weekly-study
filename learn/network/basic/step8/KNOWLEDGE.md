# Step 8 で登場した用語・概念

このステップで**新たに**登場した用語・概念をまとめます。
VNet・サブネット・NSG・VM・プライベート IP・Run Command による疎通確認・名前解決（Private DNS Zone / A レコード /
VNet リンク）など、Step 1〜7 でカバーした内容は前提として含めません。

## ネットワーク全般の概念

### マネージドサービス（PaaS）と公開エンドポイント
* ストレージやデータベースのような **PaaS** は、自分で VM を建てる代わりに、事業者が運用するサービスを使う。
* それらは既定で **公衆インターネット上の公開エンドポイント**（公開 FQDN + 公開 IP）を持つ。
  つまり「VNet の外」にいて、インターネット経由でアクセスするのが既定の姿。
* これを VNet の内側（プライベート IP）に引き込みたい、というのが本ステップの動機。

### プライベート接続（private connectivity）
* サービスへの通信を、**公衆インターネットを経由させず**、自分の VNet 内の**プライベート IP**で完結させる考え方。
* 利点：
  * 通信がインターネットに出ない（経路上の露出が減る）。
  * サービス側の**公開エンドポイントを閉じても**、プライベート経路だけは生かせる（攻撃面を絞る＝閉域化）。
* 「**名前は同じ・向き先だけプライベート IP**」にするのがポイントで、これは名前解決（DNS）の仕事。

### 「公開を閉じる」と「プライベートで開ける」は別物
* **公開を閉じる**：サービス側のスイッチで、公開エンドポイントからの受け入れを止める。
* **プライベートで開ける**：自分の VNet 側に入口（後述の Private Endpoint）を用意する。
* この 2 つは独立して出し入れできる。両方を組み合わせると「公開は閉じ、プライベートだけ通す」が成立する。
  （NSG/UDR/NAT GW/DNS リンクと同じく、片方ずつ出し入れして因果を切り分けられる。）

## Azure 固有の用語（上記概念の具体例）

### Private Endpoint（プライベートエンドポイント）
* 接続先 PaaS への入口として、**自分のサブネットに生やす NIC**。VNet 内の**プライベート IP**（例 `10.0.1.x`）を持つ。
* この NIC が、裏側の PaaS（の特定サブリソース）への Private Link 接続を張る。
  VM から見れば「サービスが VNet 内のプライベート IP に居る」ように扱える。
* Bicep では `Microsoft.Network/privateEndpoints` で定義し、`privateLinkServiceConnections` に
  接続先（`privateLinkServiceId`）と**サブリソース**（`groupIds`）を指定する。

### Private Link / groupId（サブリソース）
* **Private Link** は「サービスを VNet 内のプライベート IP で公開する」仕組みの総称。Private Endpoint はその利用者側の入口。
* 1 つのサービスでも機能ごとに繋ぎ先が分かれる。Storage なら **groupId** = `blob` / `file` / `queue` / `table` / `web` / `dfs`。
  本ステップは `blob` だけに Private Endpoint を張った（他機能が必要なら groupId ごとに PE を増やす）。

### Private DNS Zone `privatelink.<service>`（名前を “プライベート IP” に向ける）
* Private Endpoint 用には、**サービスごとに決まった名前のゾーン**を使う。blob は `privatelink.blob.core.windows.net`。
* 公開 FQDN `<account>.blob.core.windows.net` は内部的に
  `<account>.blob.core.windows.net` → **CNAME** → `<account>.privatelink.blob.core.windows.net`
  という形を取る。このゾーンがリンクされた VNet 内では、その `privatelink` 名が
  **Private Endpoint のプライベート IP（A レコード）** に解決される。
* だから**アプリは URL を変えなくてよい**。同じ公開 FQDN のまま、解決される IP だけがプライベートに変わる。
  リンクが無ければ公開 FQDN は公衆 DNS の答え（=公開 IP）に解決される（Step7 の `unlink`/`link` と同じ切り分け）。

### Private DNS Zone Group（PE の IP をゾーンへ自動登録）
* `Microsoft.Network/privateEndpoints/privateDnsZoneGroups`。Private Endpoint と Private DNS Zone を結びつけ、
  PE のプライベート IP を、対応するゾーンに **A レコードとして自動で作成・維持**する。
* Step7 の「手動レコード」を手で書く代わりに、PE 専用の自動連携でレコードが保たれる。PE の IP が変わっても追従する。

### `publicNetworkAccess`（Storage の公開エンドポイント開閉）
* Storage アカウントの `publicNetworkAccess` を **`Disabled`** にすると、公衆インターネット側の公開エンドポイントを閉じる。
  → このアカウントへは Private Endpoint 経由（プライベート IP）でしか到達できなくなる。
* 名前解決（DNS リンク）とは**独立**したスイッチ。`disable-public`/`enable-public` で出し入れしても、
  Private Endpoint 経由の到達性は変わらない。`allowBlobPublicAccess: false` は別レイヤ（匿名公開の可否）。

### Private Endpoint 用サブネットの `privateEndpointNetworkPolicies`
* Private Endpoint を置くサブネットでは、PE 向けのネットワークポリシーを `Disabled` にするのが定石
  （本ステップは `snet-pe` に設定）。PE への適切なルーティングを妨げないための作法。

## このステップの要点
* PaaS への通信は既定で**公開エンドポイント（インターネット経由）**。これを VNet 内に引き込むのが Private Endpoint。
* **Private Endpoint = 自分のサブネットに生える NIC**。PaaS への**プライベート IP の入口**になる（groupId で機能を選ぶ）。
* **Private DNS Zone `privatelink.…`** が、**同じ公開 FQDN** を**プライベート IP に解決**させる（Step7 の名前解決の延長）。
  **Zone Group** が PE の IP をゾーンへ自動登録する。
* **名前解決**（`unlink`/`link`）と**公開アクセス**（`disable-public`/`enable-public`）は**独立**に出し入れでき、
  両方を絞ると「公開は閉じ、プライベートだけ通す」閉域構成になる。
