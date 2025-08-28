#!/bin/bash

set -e

echo "开始手动构建 QWindowKit..."

BUILD_TYPE="Release"
BUILD_STATIC="ON"
ENABLE_WIDGETS="ON"
ENABLE_QUICK="OFF"
ENABLE_QT_WINDOW_CONTEXT="OFF"
ENABLE_STYLE_AGENT="OFF"
ENABLE_WINDOWS_SYSTEM_BORDERS="OFF"

# Qt PATH
QT_PREFIX="/opt/homebrew/Cellar/qt/6.9.0_1/"
QT_INCLUDE_DIR="${QT_PREFIX}/include"
QT_LIB_DIR="${QT_PREFIX}/lib"
QT_LIBEXEC_DIR="${QT_PREFIX}/share/qt/libexec"

# Complier and flags
CXX="clang++"
CXXFLAGS="-std=c++17 -fPIC -fvisibility=hidden -fvisibility-inlines-hidden"

if [ "$BUILD_TYPE" = "Debug" ]; then
    CXXFLAGS="$CXXFLAGS -g -O0 -DDEBUG"
else
    CXXFLAGS="$CXXFLAGS -O2 -DNDEBUG"
fi

# Preprocessor definitions - CMake-compatible macro logic
# Define as 1 when feature is enabled, -1 when disabled
DEFINES=""

if [ "$ENABLE_WINDOWS_SYSTEM_BORDERS" = "ON" ]; then
    DEFINES="$DEFINES -DQWINDOWKIT_ENABLE_WINDOWS_SYSTEM_BORDERS=1"
else
    DEFINES="$DEFINES -DQWINDOWKIT_ENABLE_WINDOWS_SYSTEM_BORDERS=-1"
fi

if [ "$ENABLE_STYLE_AGENT" = "ON" ]; then
    DEFINES="$DEFINES -DQWINDOWKIT_ENABLE_STYLE_AGENT=1"
else
    DEFINES="$DEFINES -DQWINDOWKIT_ENABLE_STYLE_AGENT=-1"
fi

if [ "$ENABLE_QT_WINDOW_CONTEXT" = "ON" ]; then
    DEFINES="$DEFINES -DQWINDOWKIT_ENABLE_QT_WINDOW_CONTEXT=1"
else
    DEFINES="$DEFINES -DQWINDOWKIT_ENABLE_QT_WINDOW_CONTEXT=-1"
fi

echo "DEFINES: $DEFINES"

mkdir -p build/include/QWKCore
mkdir -p build/include/QWKCore/private
mkdir -p build/include/QWKWidgets
mkdir -p build/lib

cp src/core/style/styleagent.h build/include/QWKCore/styleagent.h 

# Generate qwkconfig.h
cat > build/include/QWKCore/qwkconfig.h << EOF
#ifndef QWKCONFIG_H
#define QWKCONFIG_H

#define QWINDOWKIT_ENABLE_QT_WINDOW_CONTEXT $([ "$ENABLE_QT_WINDOW_CONTEXT" = "ON" ] && echo "1" || echo "-1")
#define QWINDOWKIT_ENABLE_STYLE_AGENT $([ "$ENABLE_STYLE_AGENT" = "ON" ] && echo "1" || echo "-1")
#define QWINDOWKIT_ENABLE_WINDOWS_SYSTEM_BORDERS $([ "$ENABLE_WINDOWS_SYSTEM_BORDERS" = "ON" ] && echo "1" || echo "-1")

#endif // QWKCONFIG_H
EOF

# Copy header files
echo "复制头文件..."
cp src/core/*.h build/include/QWKCore/
cp src/core/*_p.h build/include/QWKCore/private/ 2>/dev/null || true
cp src/core/contexts/*_p.h build/include/QWKCore/private/ 2>/dev/null || true
cp src/core/kernel/*_p.h build/include/QWKCore/private/ 2>/dev/null || true
cp src/core/shared/*_p.h build/include/QWKCore/private/ 2>/dev/null || true
if [ "$ENABLE_STYLE_AGENT" = "ON" ]; then
    cp src/core/style/*_p.h build/include/QWKCore/private/ 2>/dev/null || true
fi
if [ "$ENABLE_WIDGETS" = "ON" ]; then
    cp src/widgets/*.h build/include/QWKWidgets/
fi

# Qt 模块配置
QT_MODULES="Core Gui"
if [ "$ENABLE_WIDGETS" = "ON" ]; then
    QT_MODULES="$QT_MODULES Widgets"
fi

# 生成 Qt 编译标志
QT_CFLAGS=""
QT_LIBS=""
for module in $QT_MODULES; do
    QT_CFLAGS="$QT_CFLAGS $(pkg-config --cflags Qt6${module})"
    QT_LIBS="$QT_LIBS $(pkg-config --libs Qt6${module})"
done

# 添加 Qt 私有头文件路径
QT_VERSION=$(pkg-config --modversion Qt6Core)
QT_FRAMEWORK_PATH="${QT_PREFIX}/lib"

# Qt 私有头文件路径 - 顺序很重要：先公共头文件，再私有头文件
QT_PRIVATE_INCLUDES="-I${QT_FRAMEWORK_PATH}/QtCore.framework/Versions/A/Headers/${QT_VERSION}"
QT_PRIVATE_INCLUDES="$QT_PRIVATE_INCLUDES -I${QT_FRAMEWORK_PATH}/QtGui.framework/Versions/A/Headers/${QT_VERSION}"
QT_PRIVATE_INCLUDES="$QT_PRIVATE_INCLUDES -I${QT_FRAMEWORK_PATH}/QtGui.framework/Versions/A/Headers/${QT_VERSION}/QtGui"
QT_PRIVATE_INCLUDES="$QT_PRIVATE_INCLUDES -I${QT_FRAMEWORK_PATH}/QtCore.framework/Versions/A/Headers/${QT_VERSION}/QtCore"
echo $QT_PRIVATE_INCLUDES

# 检查私有头文件是否存在
if [ ! -f "${QT_FRAMEWORK_PATH}/QtCore.framework/Versions/A/Headers/${QT_VERSION}/QtCore/private/qobject_p.h" ]; then
    echo "警告: Qt 私有头文件未找到，可能需要安装 Qt 开发包"
fi

# 包含目录 - 顺序：项目构建目录，项目源码，Qt公共头文件，Qt私有头文件
INCLUDES="-Ibuild/include -Isrc/core -Isrc/core/contexts -Isrc/core/kernel -Isrc/core/shared -Isrc -I${QT_INCLUDE_DIR} ${QT_PRIVATE_INCLUDES}"

# 构建 QWKCore
echo "构建 QWKCore..."

# 收集 core 源文件 - 基于 CMakeLists.txt
CORE_SOURCES=""
CORE_SOURCES="$CORE_SOURCES src/core/qwkglobal.cpp"
CORE_SOURCES="$CORE_SOURCES src/core/windowagentbase.cpp"
CORE_SOURCES="$CORE_SOURCES src/core/windowitemdelegate.cpp"
CORE_SOURCES="$CORE_SOURCES src/core/kernel/nativeeventfilter.cpp"
CORE_SOURCES="$CORE_SOURCES src/core/kernel/sharedeventfilter.cpp"
CORE_SOURCES="$CORE_SOURCES src/core/kernel/winidchangeeventfilter.cpp"
CORE_SOURCES="$CORE_SOURCES src/core/contexts/abstractwindowcontext.cpp"

# 平台特定源文件
case "$(uname)" in
    Darwin)
        if [ "$ENABLE_QT_WINDOW_CONTEXT" = "ON" ]; then
            CORE_SOURCES="$CORE_SOURCES src/core/contexts/qtwindowcontext.cpp"
        else
            CORE_SOURCES="$CORE_SOURCES src/core/contexts/cocoawindowcontext.mm"
        fi
        PLATFORM_LIBS="-framework Foundation -framework Cocoa -framework AppKit"
        
        # 添加 StyleAgent 相关文件
        if [ "$ENABLE_STYLE_AGENT" = "ON" ]; then
            CORE_SOURCES="$CORE_SOURCES src/core/style/styleagent.cpp"
            CORE_SOURCES="$CORE_SOURCES src/core/style/styleagent_mac.mm"
        fi
        ;;
    Linux)
        if [ "$ENABLE_QT_WINDOW_CONTEXT" = "ON" ]; then
            CORE_SOURCES="$CORE_SOURCES src/core/contexts/qtwindowcontext.cpp"
        else
            CORE_SOURCES="$CORE_SOURCES src/core/contexts/qtwindowcontext.cpp"  # Linux 总是使用 Qt 实现
        fi
        PLATFORM_LIBS=""
        if [ "$ENABLE_STYLE_AGENT" = "ON" ]; then
            CORE_SOURCES="$CORE_SOURCES src/core/style/styleagent.cpp"
            CORE_SOURCES="$CORE_SOURCES src/core/style/styleagent_linux.cpp"
        fi
        ;;
    MINGW*|MSYS*|CYGWIN*)
        if [ "$ENABLE_QT_WINDOW_CONTEXT" = "ON" ]; then
            CORE_SOURCES="$CORE_SOURCES src/core/contexts/qtwindowcontext.cpp"
        else
            CORE_SOURCES="$CORE_SOURCES src/core/contexts/win32windowcontext.cpp"
        fi
        PLATFORM_LIBS="-luxtheme"
        if [ "$ENABLE_STYLE_AGENT" = "ON" ]; then
            CORE_SOURCES="$CORE_SOURCES src/core/style/styleagent.cpp"
            CORE_SOURCES="$CORE_SOURCES src/core/style/styleagent_win.cpp"
        fi
        ;;
esac

echo "CORE_SOURCES: $CORE_SOURCES"

# 处理需要 MOC 的文件
MOC_HEADERS=""
MOC_SOURCES=""

# 检查所有头文件是否需要 MOC 处理
MOC_HEADER_LIST="src/core/windowagentbase.h"
if [ "$ENABLE_STYLE_AGENT" = "ON" ]; then
    MOC_HEADER_LIST="$MOC_HEADER_LIST src/core/style/styleagent.h"
fi

# 添加 window context 头文件
MOC_HEADER_LIST="$MOC_HEADER_LIST src/core/contexts/abstractwindowcontext_p.h"
if [ "$ENABLE_QT_WINDOW_CONTEXT" = "ON" ]; then
    MOC_HEADER_LIST="$MOC_HEADER_LIST src/core/contexts/qtwindowcontext_p.h"
else
    case "$(uname)" in
        Darwin)
            MOC_HEADER_LIST="$MOC_HEADER_LIST src/core/contexts/cocoawindowcontext_p.h"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            MOC_HEADER_LIST="$MOC_HEADER_LIST src/core/contexts/win32windowcontext_p.h"
            ;;
    esac
fi

for header in $MOC_HEADER_LIST; do
    if [ -f "$header" ] && grep -q "Q_OBJECT" "$header"; then
        moc_file="build/moc_$(basename "$header" _p.h).cpp"
        if [[ "$header" == *"_p.h" ]]; then
            moc_file="build/moc_$(basename "$header" _p.h).cpp"
        else
            moc_file="build/moc_$(basename "$header" .h).cpp"
        fi
        echo "运行 MOC: $header -> $moc_file"
        ${QT_LIBEXEC_DIR}/moc "$header" -o "$moc_file" $INCLUDES $DEFINES
        MOC_SOURCES="$MOC_SOURCES $moc_file"
    fi
done

# 编译 QWKCore
if [ "$BUILD_STATIC" = "ON" ]; then
    echo "编译静态库 libQWKCore.a..."
    $CXX $CXXFLAGS $INCLUDES $DEFINES $QT_CFLAGS -c $CORE_SOURCES $MOC_SOURCES
    ar rcs build/lib/libQWKCore.a *.o
    rm *.o
else
    echo "编译动态库 libQWKCore..."
    $CXX $CXXFLAGS $INCLUDES $DEFINES $QT_CFLAGS -shared \
        $CORE_SOURCES $MOC_SOURCES \
        $QT_LIBS $PLATFORM_LIBS \
        -o build/lib/libQWKCore.dylib  # 在 Linux 上用 .so，在 Windows 上用 .dll
fi

# 构建 QWKWidgets (如果启用)
if [ "$ENABLE_WIDGETS" = "ON" ]; then
    echo "构建 QWKWidgets..."
    
    WIDGETS_SOURCES=""
    WIDGETS_SOURCES="$WIDGETS_SOURCES src/widgets/widgetwindowagent.cpp"
    WIDGETS_SOURCES="$WIDGETS_SOURCES src/widgets/widgetitemdelegate.cpp"
    
    # 添加平台特定的 widgets 源文件
    case "$(uname)" in
        Darwin)
            WIDGETS_SOURCES="$WIDGETS_SOURCES src/widgets/widgetwindowagent_mac.cpp"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            WIDGETS_SOURCES="$WIDGETS_SOURCES src/widgets/widgetwindowagent_win.cpp"
            ;;
    esac
    
    # 处理 widgets 的 MOC 文件
    WIDGETS_MOC_SOURCES=""
    for header in src/widgets/*.h; do
        if [ -f "$header" ] && grep -q "Q_OBJECT" "$header"; then
            moc_file="build/moc_$(basename "$header" .h).cpp"
            echo "运行 MOC: $header -> $moc_file"
            ${QT_LIBEXEC_DIR}/moc "$header" -o "$moc_file" $INCLUDES $DEFINES
            WIDGETS_MOC_SOURCES="$WIDGETS_MOC_SOURCES $moc_file"
        fi
    done
    
    # 编译 QWKWidgets
    if [ "$BUILD_STATIC" = "ON" ]; then
        echo "编译静态库 libQWKWidgets.a..."
        $CXX $CXXFLAGS $INCLUDES $DEFINES $QT_CFLAGS -c $WIDGETS_SOURCES $WIDGETS_MOC_SOURCES
        ar rcs build/lib/libQWKWidgets.a *.o
        rm *.o
    else
        echo "编译动态库 libQWKWidgets..."
        $CXX $CXXFLAGS $INCLUDES $DEFINES $QT_CFLAGS -shared \
            $WIDGETS_SOURCES $WIDGETS_MOC_SOURCES \
            $QT_LIBS -Lbuild/lib -lQWKCore \
            -o build/lib/libQWKWidgets.dylib
    fi
fi

echo "构建完成！"
echo "头文件目录: build/include/"
echo "库文件目录: build/lib/"