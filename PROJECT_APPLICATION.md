# MoonNATS 项目申报书

**基本信息**

- 项目名称：MoonNATS——NATS 协议与可恢复客户端状态机
- 参赛者：唐仕吉
- 联系方式：t1622051617@qq.com / 13384247418
- GitHub 仓库链接：https://github.com/TangShiJi/moonnats
- 项目方向：MoonBit 消息中间件 / NATS 协议基础设施
- 项目性质：原创项目（非移植，Apache-2.0）

**项目简介、价值与通用性**

MoonBit 服务若要接入 NATS，目前只能自行处理以 CRLF 分隔的控制行、按字节计长的二进制载荷、任意网络分片、HMSG 头部、SID 生命周期、PING/PONG、请求收件箱及断线重放；把这些逻辑直接写进业务，最常见的结果是 Unicode 长度算错、半包误解析、重连后漏订阅或无界缓存。MoonNATS 把这部分做成与网络运行时解耦的协议与客户端状态机，同一核心可接 native TCP、WebSocket 桥或测试模拟器。它不是进程内事件总线，也不实现 Broker；补的是 MoonBit 与现有 NATS 集群之间缺失的可复用客户端基础层。

2026-10-13 我更新并检索了 mooncakes.io 本地全量索引（2,968 个模块）及 GitHub：未发现 NATS/JetStream/MoonBit 客户端。`xvyve123/moonflow` 是进程内事件总线，`zbhzs1/moonbit-mqtt` 是不同协议的 MQTT 编解码器，`liying-han/moonresilience` 提供通用重试与熔断，均不解析 NATS wire protocol、管理 NATS SID 或完成请求-响应；本项目与我已有的表单状态项目及 MoonPageFlow 分页项目也无功能重合。

**完整使用场景**

1. 事件驱动服务：订单服务发布 `orders.created` 二进制事件，审计/通知服务以 `orders.*` 订阅；网络分片、心跳和重连由统一状态机处理，业务只消费完整消息。
2. 水平扩展任务处理：多个图片处理实例用同一 queue group 订阅 `jobs.resize`，由 NATS 每次只投递给一名成员；客户端维护 SID、最大投递数并在重连后按剩余额度恢复订阅。
3. 服务间请求-响应：API 网关向 `profile.lookup` 发请求，库原子排队 `SUB inbox`、`UNSUB 1`、`PUB reply-to`，以单调时钟处理超时，并识别无响应者状态头。
4. 边缘/多运行时接入：native TCP、浏览器 WebSocket 桥或嵌入式循环只实现读写适配，复用同一套可在 wasm-gc 验证的协议、背压、发现与恢复行为。

**核心功能、实现路径与工程边界**

- 必做 NATS Core：INFO/CONNECT/PUB/HPUB/SUB/UNSUB/MSG/HMSG/PING/PONG/+OK/-ERR，主题通配、queue group、NATS/1.0 多值头和二进制安全增量解析；
- 必做客户端行为：显式状态迁移、资源上限与背压、订阅分发/自动退订、请求-响应/无响应者、INFO 节点发现、退避重连、订阅重放；提供 native TCP 适配及 `nats-server` 黑盒验证；
- 实现上先以“控制行元数据 + 精确 payload 字节数”确定帧边界，再解析内容；网络、时钟、随机抖动均由宿主注入，使半包、超时和重连可确定复现；
- 本期不做 JetStream 持久化 API、Broker、NKey/JWT、WebSocket 传输，也不自研 TLS；TLS 交给传输层。当前 MVP 已有 2,394 行有效核心 MoonBit 源码、54 项 native/wasm-gc 测试和四个可运行示例。

**可直接验收的行为标准**

任意字节边界拆分的 MSG/HMSG 只能产出一次完整消息；Unicode 与含 CRLF 的二进制载荷按字节计长；畸形长度、未知 SID、头部注入和超限输入返回结构化错误且缓存复位；请求三帧要么全部入队要么均不生效；断线后按剩余自动退订额度重放；本地 `nats-server` 完成 pub/sub、queue、request/reply、服务重启恢复；Windows/Ubuntu 上 native 与 wasm-gc 的格式检查、构建、54+ 测试、示例和源码门槛全部通过。

**原创与提交说明**

本项目为基于公开 NATS Client Protocol 规范的原创 clean-room 实现，未移植或复制任何现有客户端源码，故无上游移植许可证；采用 Apache-2.0。仓库现有不少于 10 个有效提交，按主题语义、头部模型、编码、增量解码、订阅、客户端生命周期、请求、重连、下游示例和模糊/边界验证分别形成可独立审查的代码与测试，不以空提交或机械拆分凑数。
