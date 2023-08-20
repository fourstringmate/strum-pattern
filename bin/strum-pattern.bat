@echo off
rem Wrapper for Strum Pattern


rem Check whether Ruby is available on the system.
where ruby >nul || (
    echo No Ruby on the system >&2
    exit /b 1
)

rem Get the path of current batch script.
set cwd=%~dp0
rem Get the directory to our Ruby script.
set libexec=%cwd%..\libexec

rem Run the Ruby script and pass command-line arguments to it.
ruby %libexec%\strum-pattern.rb %*