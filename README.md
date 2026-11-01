# 端侧姿态跌倒监护

面向养老监护的单路视频处理系统。FPGA完成图像采集、灰度/高斯/直方图均衡预处理、JPEG编码和PCIe传输；RK3576完成姿态推理、跌倒判别和录像；PC端提供配置、预览与复盘界面。

## 工程入口

| 目录 | 内容及入口 |
|---|---|
| 01_FPGA | 安路TD工程 `elderly_monitor.al`，器件PH1A90SEG324，顶层 `imx415_pcie_top` |
| 02_RK | 板端程序，控制入口 `python/control_field1382.py`，推理入口 `python/live_pose1420.py` |
| 03_PC | 桌面界面 `workspace/field_console/qt_desktop.py` |
| 04_代码来源 | 文件来源分类、第三方许可证 |
| 05_测试 | Python测试与RTL仿真 |

FPGA工程保留源文件顺序、约束和编译属性，使用包内相对路径。RK依赖对应内核的PCIe驱动、Python、RKNNLite、numpy、OpenCV和GStreamer；PC依赖见 `03_PC/requirements.txt`。板端程序保留现有部署路径和文件摘要校验，`02_RK/注释阅读`为关键模块的阅读副本。

## 代码来源

FPGA的 `src/official` 为官方例程，`modified_official` 为官方基础修改，`project` 为项目新增模块，`third_party` 和 `modified_third_party` 为第三方组件及其修改。仅换行差异的文件以 `04_代码来源/代码来源.csv` 为准。厂商IP及外部组件保留各自版权声明。

JPEG编码器基于mjpegZero；姿态检测使用预训练YOLOv8n-pose转换模型。各部分按原有授权使用，本仓库不对官方和第三方代码重新授予许可。
