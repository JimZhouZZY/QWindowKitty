-- QWindowKit xmake.lua
-- Based on the build.sh script configuration

set_project("QWindowKit")
set_version("1.0.0")

-- Set languages and policies
set_languages("c++17")
add_rules("mode.debug", "mode.release")

-- Add options for different features
option("widgets")
    set_default(true)
    set_description("Enable QWKWidgets")
option_end()

option("quick")
    set_default(false)
    set_description("Enable QWKQuick")
option_end()

option("qt_window_context")
    set_default(false)
    set_description("Enable Qt Window Context")
option_end()

option("style_agent")
    set_default(false)
    set_description("Enable Style Agent")
option_end()

option("windows_system_borders")
    set_default(false)
    set_description("Enable Windows System Borders")
option_end()

option("build_static")
    set_default(true)
    set_description("Build static libraries")
option_end()

-- Qt requirements
add_requires("qt6core", "qt6gui")
if has_config("widgets") then
    add_requires("qt6widgets")
end

-- Configure target for QWKCore
target("QWKCore")
    -- Set target type
    if has_config("build_static") then
        set_kind("static")
    else
        set_kind("shared")
    end

    -- Language settings
    set_languages("c++17")
    
    -- Platform specific flags
    if is_plat("windows") then
        set_encodings("utf-8")
        add_defines("UNICODE", "_UNICODE")
        add_syslinks("user32", "dwmapi", "uxtheme")
    elseif is_plat("macosx") then
        add_frameworks("Foundation", "Cocoa", "AppKit")
        add_mxflags("-fno-objc-arc")  -- Disable ARC for manual memory management
    elseif is_plat("linux") then
        add_syslinks("m", "dl")
    end

    -- Compiler flags
    add_cxxflags("-fPIC", "-fvisibility=hidden", "-fvisibility-inlines-hidden")
    
    -- Generate config header before build
    before_build(function (target)
        -- Create build directories
        os.mkdir("$(buildir)/include/QWKCore")
        os.mkdir("$(buildir)/include/QWKCore/private")
        
        -- Generate qwkconfig.h
        local config_content = [[
#ifndef QWKCONFIG_H
#define QWKCONFIG_H

#define QWINDOWKIT_ENABLE_QT_WINDOW_CONTEXT ]] .. 
        (has_config("qt_window_context") and "1" or "-1") .. [[

#define QWINDOWKIT_ENABLE_STYLE_AGENT ]] ..
        (has_config("style_agent") and "1" or "-1") .. [[

#define QWINDOWKIT_ENABLE_WINDOWS_SYSTEM_BORDERS ]] ..
        (has_config("windows_system_borders") and "1" or "-1") .. [[


#endif // QWKCONFIG_H
]]
        io.writefile("$(buildir)/include/QWKCore/qwkconfig.h", config_content)
        
        -- Copy header files
        os.cp("src/core/*.h", "$(buildir)/include/QWKCore/")
        os.trycp("src/core/*_p.h", "$(buildir)/include/QWKCore/private/")
        os.trycp("src/core/contexts/*_p.h", "$(buildir)/include/QWKCore/private/")
        os.trycp("src/core/kernel/*_p.h", "$(buildir)/include/QWKCore/private/")
        os.trycp("src/core/shared/*_p.h", "$(buildir)/include/QWKCore/private/")
        
        if has_config("style_agent") then
            os.trycp("src/core/style/*_p.h", "$(buildir)/include/QWKCore/private/")
            os.cp("src/core/style/styleagent.h", "$(buildir)/include/QWKCore/styleagent.h")
        end

        -- Generate MOC files manually for headers with Q_OBJECT
        local moc_headers = {
            "src/core/windowagentbase.h",
            "src/core/contexts/abstractwindowcontext_p.h"
        }
        
        -- Add platform-specific headers
        if is_plat("macosx") then
            if has_config("qt_window_context") then
                table.insert(moc_headers, "src/core/contexts/qtwindowcontext_p.h")
            else
                table.insert(moc_headers, "src/core/contexts/cocoawindowcontext_p.h")
            end
        elseif is_plat("windows") then
            if has_config("qt_window_context") then
                table.insert(moc_headers, "src/core/contexts/qtwindowcontext_p.h")
            else
                table.insert(moc_headers, "src/core/contexts/win32windowcontext_p.h")
            end
        elseif is_plat("linux") then
            table.insert(moc_headers, "src/core/contexts/qtwindowcontext_p.h")
        end
        
        -- Add style agent header if enabled
        if has_config("style_agent") then
            table.insert(moc_headers, "src/core/style/styleagent.h")
        end

        -- Generate MOC files
        local qt_dir = "/opt/homebrew"
        local moc_exe = qt_dir .. "/share/qt/libexec/moc"
        local buildir = path.absolute("build/macosx/arm64")
        os.mkdir(buildir)
        
        for _, header in ipairs(moc_headers) do
            if os.isfile(header) then
                local basename = path.basename(header):gsub("_p%.h$", ""):gsub("%.h$", "")
                local moc_file = buildir .. "/moc_" .. basename .. ".cpp"
                local includes = "-Ibuild/include -Isrc/core -Isrc/core/contexts -Isrc/core/kernel -Isrc/core/shared -Isrc"
                local defines = "-DQWINDOWKIT_ENABLE_QT_WINDOW_CONTEXT=" .. (has_config("qt_window_context") and "1" or "-1")
                defines = defines .. " -DQWINDOWKIT_ENABLE_STYLE_AGENT=" .. (has_config("style_agent") and "1" or "-1")
                defines = defines .. " -DQWINDOWKIT_ENABLE_WINDOWS_SYSTEM_BORDERS=" .. (has_config("windows_system_borders") and "1" or "-1")
                
                print("Generating MOC: " .. header .. " -> " .. moc_file)
                local args = {header, "-o", moc_file}
                -- Add include and define arguments separately
                for arg in includes:gmatch("%S+") do
                    table.insert(args, arg)
                end
                for arg in defines:gmatch("%S+") do
                    table.insert(args, arg)
                end
                
                os.execv(moc_exe, args)
            end
        end
    end)

    -- Include directories
    add_includedirs("$(buildir)/include", {public = true})
    add_includedirs("src/core", "src/core/contexts", "src/core/kernel", "src/core/shared", "src")
    
    -- Add Qt private headers
    if is_plat("macosx") then
        local qt_path = "/opt/homebrew"
        local qt_ver = "6.9.0"
        add_includedirs(qt_path .. "/lib/QtCore.framework/Versions/A/Headers/" .. qt_ver)
        add_includedirs(qt_path .. "/lib/QtGui.framework/Versions/A/Headers/" .. qt_ver)
        add_includedirs(qt_path .. "/lib/QtGui.framework/Versions/A/Headers/" .. qt_ver .. "/QtGui")
        add_includedirs(qt_path .. "/lib/QtCore.framework/Versions/A/Headers/" .. qt_ver .. "/QtCore")
    elseif is_plat("linux") then
        -- For Linux, try common Qt paths
        local qt_paths = {"/usr/include", "/usr/local/include"}
        for _, qt_path in ipairs(qt_paths) do
            add_includedirs(qt_path .. "/QtCore/private")
            add_includedirs(qt_path .. "/QtGui/private")
        end
    end

    -- Feature-based definitions
    if has_config("qt_window_context") then
        add_defines("QWINDOWKIT_ENABLE_QT_WINDOW_CONTEXT=1")
    else
        add_defines("QWINDOWKIT_ENABLE_QT_WINDOW_CONTEXT=-1")
    end
    
    if has_config("style_agent") then
        add_defines("QWINDOWKIT_ENABLE_STYLE_AGENT=1")
    else
        add_defines("QWINDOWKIT_ENABLE_STYLE_AGENT=-1")
    end
    
    if has_config("windows_system_borders") then
        add_defines("QWINDOWKIT_ENABLE_WINDOWS_SYSTEM_BORDERS=1")
    else
        add_defines("QWINDOWKIT_ENABLE_WINDOWS_SYSTEM_BORDERS=-1")
    end

    -- Core source files
    add_files("src/core/qwkglobal.cpp")
    add_files("src/core/windowagentbase.cpp")
    add_files("src/core/windowitemdelegate.cpp")
    add_files("src/core/kernel/nativeeventfilter.cpp")
    add_files("src/core/kernel/sharedeventfilter.cpp")
    add_files("src/core/kernel/winidchangeeventfilter.cpp")
    add_files("src/core/contexts/abstractwindowcontext.cpp")

    -- Platform-specific source files
    if is_plat("windows") then
        if has_config("qt_window_context") then
            add_files("src/core/contexts/qtwindowcontext.cpp")
        else
            add_files("src/core/contexts/win32windowcontext.cpp")
        end
        add_files("src/core/qwindowkit_windows.cpp")
        
        if has_config("style_agent") then
            add_files("src/core/style/styleagent.cpp")
            add_files("src/core/style/styleagent_win.cpp")
        end
    elseif is_plat("macosx") then
        if has_config("qt_window_context") then
            add_files("src/core/contexts/qtwindowcontext.cpp")
        else
            add_files("src/core/contexts/cocoawindowcontext.mm")
        end
        
        if has_config("style_agent") then
            add_files("src/core/style/styleagent.cpp")
            add_files("src/core/style/styleagent_mac.mm")
        end
    elseif is_plat("linux") then
        add_files("src/core/contexts/qtwindowcontext.cpp")  -- Linux always uses Qt implementation
        
        if has_config("style_agent") then
            add_files("src/core/style/styleagent.cpp")
            add_files("src/core/style/styleagent_linux.cpp")
        end
    end

    -- Qt packages
    add_packages("qt6core", "qt6gui")

    -- Comment out Qt rules for now to avoid conflicts
    -- add_rules("qt.static")
    
    -- Manually add MOC source files that will be generated
    add_files("build/macosx/arm64/moc_windowagentbase.cpp")
    add_files("build/macosx/arm64/moc_abstractwindowcontext_p.cpp")
    
    if is_plat("macosx") then
        if has_config("qt_window_context") then
            add_files("build/macosx/arm64/moc_qtwindowcontext_p.cpp")
        else
            add_files("build/macosx/arm64/moc_cocoawindowcontext_p.cpp")
        end
    elseif is_plat("windows") then
        if has_config("qt_window_context") then
            add_files("build/windows/x64/moc_qtwindowcontext_p.cpp")
        else
            add_files("build/windows/x64/moc_win32windowcontext_p.cpp")
        end
    elseif is_plat("linux") then
        add_files("build/linux/x86_64/moc_qtwindowcontext_p.cpp")
    end
    
    if has_config("style_agent") then
        if is_plat("macosx") then
            add_files("build/macosx/arm64/moc_styleagent.cpp")
        elseif is_plat("windows") then
            add_files("build/windows/x64/moc_styleagent.cpp")
        elseif is_plat("linux") then
            add_files("build/linux/x86_64/moc_styleagent.cpp")
        end
    end

    -- Set install headers
    add_headerfiles("$(buildir)/include/QWKCore/**.h", {prefixdir = "QWKCore"})
    add_headerfiles("$(buildir)/include/QWKCore/private/**.h", {prefixdir = "QWKCore/private"})
target_end()

-- QWKWidgets target (optional)
if has_config("widgets") then
target("QWKWidgets")
    -- Set target type
    if has_config("build_static") then
        set_kind("static")
    else
        set_kind("shared")
    end

    -- Language settings
    set_languages("c++17")
    add_deps("QWKCore")

    -- Platform specific settings
    if is_plat("windows") then
        set_encodings("utf-8")
    elseif is_plat("macosx") then
        add_mxflags("-fno-objc-arc")
        add_frameworks("Foundation", "Cocoa", "AppKit")
    end

    -- Compiler flags
    add_cxxflags("-fPIC", "-fvisibility=hidden", "-fvisibility-inlines-hidden")

    -- Copy widgets headers before build
    before_build(function (target)
        os.mkdir("$(buildir)/include/QWKWidgets")
        os.cp("src/widgets/*.h", "$(buildir)/include/QWKWidgets/")

        -- Generate MOC files for widgets
        local moc_headers = {"src/widgets/widgetwindowagent.h"}
        local qt_dir = "/opt/homebrew"
        local moc_exe = qt_dir .. "/share/qt/libexec/moc"
        local buildir = path.absolute("build/macosx/arm64")
        os.mkdir(buildir)
        
        for _, header in ipairs(moc_headers) do
            if os.isfile(header) then
                local basename = path.basename(header):gsub("%.h$", "")
                local moc_file = buildir .. "/moc_" .. basename .. ".cpp"
                local includes = "-Ibuild/include -Isrc/widgets -Isrc"
                local defines = "-DQWINDOWKIT_ENABLE_QT_WINDOW_CONTEXT=" .. (has_config("qt_window_context") and "1" or "-1")
                defines = defines .. " -DQWINDOWKIT_ENABLE_STYLE_AGENT=" .. (has_config("style_agent") and "1" or "-1")
                defines = defines .. " -DQWINDOWKIT_ENABLE_WINDOWS_SYSTEM_BORDERS=" .. (has_config("windows_system_borders") and "1" or "-1")
                
                print("Generating MOC: " .. header .. " -> " .. moc_file)
                local args = {header, "-o", moc_file}
                -- Add include and define arguments separately
                for arg in includes:gmatch("%S+") do
                    table.insert(args, arg)
                end
                for arg in defines:gmatch("%S+") do
                    table.insert(args, arg)
                end
                
                os.execv(moc_exe, args)
            end
        end
    end)

    -- Include directories
    add_includedirs("$(buildir)/include", {public = true})
    add_includedirs("src/widgets", "src")

    -- Source files
    add_files("src/widgets/widgetwindowagent.cpp")
    add_files("src/widgets/widgetitemdelegate.cpp")

    -- Platform-specific widgets source files
    if is_plat("macosx") then
        add_files("src/widgets/widgetwindowagent_mac.cpp")
    elseif is_plat("windows") then
        add_files("src/widgets/widgetwindowagent_win.cpp")
    end

    -- Qt packages
    add_packages("qt6core", "qt6gui", "qt6widgets")

    -- Comment out Qt rules for now to avoid conflicts
    -- add_rules("qt.static")
    
    -- Add manually generated MOC files
    add_files("build/macosx/arm64/moc_widgetwindowagent.cpp")

    -- Set install headers
    add_headerfiles("$(buildir)/include/QWKWidgets/**.h", {prefixdir = "QWKWidgets"})
target_end()
end

-- QWKQuick target (optional)
if has_config("quick") then
target("QWKQuick")
    -- Set target type
    if has_config("build_static") then
        set_kind("static")
    else
        set_kind("shared")
    end

    -- Language settings
    set_languages("c++17")
    add_deps("QWKCore")

    -- Platform specific settings
    if is_plat("windows") then
        set_encodings("utf-8")
    elseif is_plat("macosx") then
        add_mxflags("-fno-objc-arc")
        add_frameworks("Foundation", "Cocoa", "AppKit")
    end

    -- Compiler flags
    add_cxxflags("-fPIC", "-fvisibility=hidden", "-fvisibility-inlines-hidden")

    -- Include directories
    add_includedirs("$(buildir)/include", {public = true})
    add_includedirs("src/quick", "src")

    -- Source files
    add_files("src/quick/quickitemdelegate.cpp")
    add_files("src/quick/quickwindowagent.cpp")
    add_files("src/quick/qwkquickglobal.cpp")

    -- Platform-specific quick source files
    if is_plat("macosx") then
        add_files("src/quick/quickwindowagent_mac.cpp")
    elseif is_plat("windows") then
        add_files("src/quick/quickwindowagent_win.cpp")
    end

    -- Qt packages
    add_packages("qt6core", "qt6gui")
    add_requires("qt6quick")
    add_packages("qt6quick")

    -- Comment out Qt rules for now to avoid conflicts
    -- add_rules("qt.static")

    -- Set install headers
    add_headerfiles("$(buildir)/include/QWKQuick/**.h", {prefixdir = "QWKQuick"})
target_end()
end

-- Clean task
task("clean-all")
    on_run(function ()
        os.rm("build")
        os.exec("xmake clean")
    end)
    set_menu {
        usage = "xmake clean-all",
        description = "Clean all build files including build directory"
    }
task_end()

-- Configuration summary
after_load(function (target)
    print("QWindowKit Configuration:")
    print("  - Build Type: " .. (is_mode("debug") and "Debug" or "Release"))
    print("  - Library Type: " .. (has_config("build_static") and "Static" or "Shared"))
    print("  - Widgets: " .. (has_config("widgets") and "Enabled" or "Disabled"))
    print("  - Quick: " .. (has_config("quick") and "Enabled" or "Disabled"))
    print("  - Qt Window Context: " .. (has_config("qt_window_context") and "Enabled" or "Disabled"))
    print("  - Style Agent: " .. (has_config("style_agent") and "Enabled" or "Disabled"))
    print("  - Windows System Borders: " .. (has_config("windows_system_borders") and "Enabled" or "Disabled"))
    print("  - Platform: " .. os.host())
end)
