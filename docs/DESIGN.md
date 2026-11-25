# 视觉与交互设计基准（3.0 CleanMyMac 对齐规范）

参考本机 `aethernative-site/src/styles/global.css` 系列基底与现代 CleanMyMac 模块舞台体系（详见 [CLEANMYMAC_ALIGNMENT_SPEC.md](CLEANMYMAC_ALIGNMENT_SPEC.md)）：

- **动态模块色彩舞台（`ModuleStagePalette` & `StageBackground`）**：浅色基底 `#F2F4FA`、深色基底 `#0E1017`，叠加随模块平滑切换的双源径向环境光晕（如智能护理青碧→靛蓝、系统清理珊瑚粉→魅影紫、空间透镜电光蓝→深海蓝、我的杂物琥珀→日落橘、性能监控薄荷绿→青翠）。
- **分组毛玻璃侧栏与立体徽章（`ModuleIconBadge`）**：超薄材质侧边栏搭配 `1pt` 顶部高光描边的圆角矩形立体渐变模块图标、胶囊计数/评分徽章与 2×2 快捷目标网格。
- **三段式舞台流与底部悬浮发光圆形主按钮（`CircularActionOrbBar`）**：支持 Hero 欢迎舞台、脉冲星环动态扫描横幅与居中悬浮发光圆形主控球（扫描 / 停止扫描 / 重扫）。
- **全原生绘制**：气泡透镜（`BubbleLensView`）、旭日图、树状图、分栏树、健康仪表环与菜单栏六宫格全部由原生 SwiftUI / Canvas 绘制，不引入 WebView 或任何前端运行时。

来源文件只读，未修改官网或其他产品的代码。
