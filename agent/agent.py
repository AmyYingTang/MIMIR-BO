#!/usr/bin/env python3
"""
Claude Code Agent - v0.6

自动化调用 Claude Code CLI 执行 Prompt 文件。
- 支持多个 Prompt 文件顺序执行
- 支持模板变量 {{variable}}，Agent 预先收集输入
- 自动检测并测试数据库连接，失败时允许重新输入
- 所有执行都是非交互模式，完全自动化

Usage:
    python agent.py run <prompt_files...> --project <project_dir>
    
Examples:
    # 单个文件
    python agent.py run ./01-init.md --project ~/voice-platform
    
    # 多个文件（按文件名排序执行）
    python agent.py run ./01.md ./02.md ./03.md --project ~/voice-platform
    
    # 通配符
    python agent.py run ./prompts/*.md --project ~/voice-platform

模板变量:
    在 Prompt 文件中使用 {{variable_name}} 格式定义变量。
    Agent 会在执行前收集所有变量的值，然后替换后执行。
    
    示例:
    ```
    Python 命令：{{python_cmd}}
    数据库名：{{db_name:voice_model_platform}}  # 带默认值
    ```
    
连接测试:
    当检测到 MySQL 相关变量时，会自动测试连接。
    连接失败时允许重新输入，直到成功或用户放弃。
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Tuple, Optional


# 匹配模板变量: {{name}} 或 {{name:default_value}}
TEMPLATE_VAR_PATTERN = re.compile(r'\{\{(\w+)(?::([^}]*))?\}\}')

# MySQL 相关变量名
MYSQL_VAR_NAMES = {'mysql_host', 'mysql_port', 'mysql_user', 'mysql_password', 'db_name'}

# 交互模式标记
INTERACTIVE_MARKER = '<!-- agent:interactive -->'


def is_interactive_prompt(content: str) -> bool:
    """检测 Prompt 是否标记为交互模式"""
    return INTERACTIVE_MARKER in content


def execute_claude_code_interactive(prompt: str, project_dir: Path) -> int:
    """
    交互模式执行 Claude Code
    用于需要用户在执行过程中确认的场景
    """
    print(f"🚀 开始执行（交互模式）...\n")
    print("=" * 60)
    print("提示：Claude Code 可能会向你提问，请在终端中直接回答")
    print("=" * 60 + "\n")
    
    try:
        # 交互模式：不用 -p
        process = subprocess.run(
            ["claude", prompt],
            cwd=project_dir,
        )
        return process.returncode
        
    except FileNotFoundError:
        print("❌ 错误: 找不到 claude 命令")
        print("   请确认已安装 Claude Code CLI:")
        print("   npm install -g @anthropic-ai/claude-code")
        return 1
    except Exception as e:
        print(f"❌ 执行出错: {e}")
        return 1


def test_mysql_connection(host: str, port: str, user: str, password: str, db_name: Optional[str] = None) -> Tuple[bool, str]:
    """
    测试 MySQL 连接
    
    Returns:
        (success, message)
    """
    try:
        import pymysql
    except ImportError:
        # 如果没有 pymysql，尝试用 mysql 命令行
        return test_mysql_connection_cli(host, port, user, password, db_name)
    
    try:
        conn = pymysql.connect(
            host=host,
            port=int(port),
            user=user,
            password=password,
            connect_timeout=5
        )
        conn.close()
        return True, "连接成功"
    except pymysql.err.OperationalError as e:
        error_code = e.args[0]
        if error_code == 1045:
            return False, "认证失败：用户名或密码错误"
        elif error_code == 2003:
            return False, f"无法连接到 {host}:{port}"
        else:
            return False, str(e)
    except Exception as e:
        return False, str(e)


def test_mysql_connection_cli(host: str, port: str, user: str, password: str, db_name: Optional[str] = None) -> Tuple[bool, str]:
    """
    使用 mysql 命令行测试连接
    """
    try:
        cmd = [
            'mysql',
            f'-h{host}',
            f'-P{port}',
            f'-u{user}',
            f'-p{password}',
            '-e', 'SELECT 1'
        ]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            return True, "连接成功"
        else:
            error = result.stderr.strip()
            if 'Access denied' in error:
                return False, "认证失败：用户名或密码错误"
            elif 'connect' in error.lower():
                return False, f"无法连接到 {host}:{port}"
            else:
                return False, error
    except FileNotFoundError:
        return True, "跳过测试（mysql 命令不可用）"
    except subprocess.TimeoutExpired:
        return False, "连接超时"
    except Exception as e:
        return False, str(e)


def read_prompt_file(prompt_path: Path) -> str:
    """读取 Prompt 文件内容"""
    if not prompt_path.exists():
        print(f"❌ Prompt 文件不存在: {prompt_path}")
        sys.exit(1)
    
    if not prompt_path.suffix.lower() in ['.md', '.txt']:
        print(f"⚠️  警告: 文件扩展名不是 .md 或 .txt，继续执行...")
    
    content = prompt_path.read_text(encoding='utf-8')
    if not content.strip():
        print(f"❌ Prompt 文件为空: {prompt_path}")
        sys.exit(1)
    
    return content


def extract_variables(prompt: str) -> List[Tuple[str, str]]:
    """
    从 Prompt 中提取模板变量
    
    Returns:
        List of (variable_name, default_value) tuples
        default_value 为 None 如果没有默认值
    """
    variables = []
    seen = set()
    
    for match in TEMPLATE_VAR_PATTERN.finditer(prompt):
        var_name = match.group(1)
        default_value = match.group(2)  # 可能为 None
        
        if var_name not in seen:
            variables.append((var_name, default_value))
            seen.add(var_name)
    
    return variables


def collect_variables(variables: List[Tuple[str, str]]) -> Dict[str, str]:
    """
    向用户收集变量值，并对特定变量组合进行连接测试
    
    Args:
        variables: List of (name, default_value) tuples
        
    Returns:
        Dict of {name: value}
    """
    if not variables:
        return {}
    
    print("\n📝 请提供以下信息：")
    print("-" * 40)
    
    values = {}
    var_names = {name for name, _ in variables}
    
    # 检查是否有 MySQL 相关变量
    has_mysql_vars = bool(var_names & MYSQL_VAR_NAMES)
    mysql_vars_to_collect = list(var_names & MYSQL_VAR_NAMES)
    
    for var_name, default_value in variables:
        if default_value:
            prompt_text = f"   {var_name} [默认: {default_value}]: "
        else:
            prompt_text = f"   {var_name}: "
        
        user_input = input(prompt_text).strip()
        
        if user_input:
            values[var_name] = user_input
        elif default_value:
            values[var_name] = default_value
            print(f"      → 使用默认值: {default_value}")
        else:
            print(f"❌ 必须提供 {var_name} 的值")
            sys.exit(1)
        
        # 收集完 MySQL 相关变量后，测试连接
        if has_mysql_vars and var_name in MYSQL_VAR_NAMES:
            # 检查是否已收集完所有 MySQL 变量
            collected_mysql = {k for k in values.keys() if k in MYSQL_VAR_NAMES}
            required_mysql = {'mysql_host', 'mysql_port', 'mysql_user', 'mysql_password'}
            
            if required_mysql <= collected_mysql:
                # 已收集完毕，测试连接
                while True:
                    print("\n   🔍 测试 MySQL 连接...")
                    success, message = test_mysql_connection(
                        host=values.get('mysql_host', 'localhost'),
                        port=values.get('mysql_port', '3306'),
                        user=values.get('mysql_user', 'root'),
                        password=values.get('mysql_password', ''),
                        db_name=values.get('db_name')
                    )
                    
                    if success:
                        print(f"   ✅ {message}")
                        break
                    else:
                        print(f"   ❌ {message}")
                        print("\n   请重新输入 MySQL 连接信息，或输入 'skip' 跳过测试：")
                        
                        # 让用户选择重新输入哪些字段
                        retry_input = input("   重新输入 (host/port/user/password/skip): ").strip().lower()
                        
                        if retry_input == 'skip':
                            print("   ⚠️  跳过连接测试，继续执行...")
                            break
                        elif retry_input == 'host':
                            new_val = input(f"   mysql_host [{values.get('mysql_host')}]: ").strip()
                            if new_val:
                                values['mysql_host'] = new_val
                        elif retry_input == 'port':
                            new_val = input(f"   mysql_port [{values.get('mysql_port')}]: ").strip()
                            if new_val:
                                values['mysql_port'] = new_val
                        elif retry_input == 'user':
                            new_val = input(f"   mysql_user [{values.get('mysql_user')}]: ").strip()
                            if new_val:
                                values['mysql_user'] = new_val
                        elif retry_input == 'password':
                            new_val = input("   mysql_password: ").strip()
                            if new_val:
                                values['mysql_password'] = new_val
                        else:
                            # 默认重新输入密码（最常见的错误）
                            new_val = input("   mysql_password: ").strip()
                            if new_val:
                                values['mysql_password'] = new_val
    
    print("-" * 40)
    return values


def fill_template(prompt: str, values: Dict[str, str]) -> str:
    """
    用收集到的值填充模板
    """
    def replacer(match):
        var_name = match.group(1)
        return values.get(var_name, match.group(0))
    
    return TEMPLATE_VAR_PATTERN.sub(replacer, prompt)


def execute_claude_code(prompt: str, project_dir: Path) -> int:
    """
    非交互模式执行 Claude Code，实时流式输出进度。
    
    使用 --output-format stream-json 获取实时事件流，
    解析每行 JSON 并打印关键信息（工具调用、文本输出等）。
    """
    import json
    
    cmd = [
        "claude", "-p",
        "--verbose",
        "--output-format", "stream-json",
        "--dangerously-skip-permissions",
        prompt,
    ]
    
    print(f"🚀 开始执行...\n")
    
    try:
        process = subprocess.Popen(
            cmd,
            cwd=project_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,  # 行缓冲
        )
        
        result_text = ""
        
        for line in process.stdout:
            line = line.strip()
            if not line:
                continue
            
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                # 非 JSON 行直接打印
                print(line)
                continue
            
            msg_type = event.get("type", "")
            
            # --- 系统消息 ---
            if msg_type == "system":
                subtype = event.get("subtype", "")
                if subtype == "init":
                    session_id = event.get("session_id", "?")
                    print(f"   🔗 会话: {session_id[:12]}...")
                # init / result 都是 system 类型
            
            # --- 助手消息（包含工具调用和文本） ---
            elif msg_type == "assistant":
                message = event.get("message", {})
                contents = message.get("content", [])
                
                for block in contents:
                    block_type = block.get("type", "")
                    
                    if block_type == "text":
                        text = block.get("text", "")
                        if text.strip():
                            # 只打印前 200 字符避免刷屏
                            preview = text[:200] + ("..." if len(text) > 200 else "")
                            print(f"   💬 {preview}")
                    
                    elif block_type == "tool_use":
                        tool_name = block.get("name", "unknown")
                        tool_input = block.get("input", {})
                        
                        if tool_name == "Bash":
                            cmd_text = tool_input.get("command", "")
                            preview = cmd_text[:120] + ("..." if len(cmd_text) > 120 else "")
                            print(f"   🔧 Bash: {preview}")
                        elif tool_name in ("Write", "Edit", "MultiEdit"):
                            file_path = tool_input.get("file_path", tool_input.get("filePath", ""))
                            print(f"   📝 {tool_name}: {file_path}")
                        elif tool_name == "Read":
                            file_path = tool_input.get("file_path", tool_input.get("filePath", ""))
                            print(f"   👁️  Read: {file_path}")
                        else:
                            print(f"   🔧 {tool_name}")
                    
                    elif block_type == "tool_result":
                        # 工具执行结果，通常很长，只显示状态
                        is_error = block.get("is_error", False)
                        if is_error:
                            content = block.get("content", "")
                            preview = str(content)[:150]
                            print(f"   ❌ 工具错误: {preview}")
            
            # --- 最终结果 ---
            elif msg_type == "result":
                subtype = event.get("subtype", "")
                cost = event.get("total_cost_usd", 0)
                duration = event.get("duration_ms", 0)
                turns = event.get("num_turns", 0)
                result_text = event.get("result", "")
                
                print(f"\n   📊 完成统计:")
                print(f"      轮次: {turns}, 耗时: {duration/1000:.1f}s, 费用: ${cost:.4f}")
                
                if subtype != "success":
                    print(f"   ⚠️  结果状态: {subtype}")
        
        # 等待进程结束
        process.wait()
        
        # 检查 stderr
        stderr_output = process.stderr.read()
        if stderr_output and process.returncode != 0:
            print(f"\n   ⚠️  stderr: {stderr_output[:300]}")
        
        return process.returncode
        
    except FileNotFoundError:
        print("❌ 错误: 找不到 claude 命令")
        print("   请确认已安装 Claude Code CLI:")
        print("   npm install -g @anthropic-ai/claude-code")
        return 1
    except Exception as e:
        print(f"❌ 执行出错: {e}")
        return 1


def run_command(args):
    """执行 run 子命令"""
    project_dir = Path(args.project).resolve()
    
    # 验证项目目录
    if not project_dir.exists():
        print(f"❌ 项目目录不存在: {project_dir}")
        sys.exit(1)
    
    if not project_dir.is_dir():
        print(f"❌ 不是目录: {project_dir}")
        sys.exit(1)
    
    # 收集所有 prompt 文件
    prompt_files = []
    for f in args.prompt_files:
        p = Path(f).resolve()
        if not p.exists():
            print(f"❌ Prompt 文件不存在: {p}")
            sys.exit(1)
        prompt_files.append(p)
    
    # 按文件名排序
    prompt_files.sort(key=lambda x: x.name)
    
    total = len(prompt_files)
    print(f"📋 共 {total} 个 Prompt 文件待执行")
    print(f"📁 项目目录: {project_dir}")
    
    # === 阶段 1: 扫描所有文件，收集所有变量 ===
    print("\n" + "=" * 60)
    print("阶段 1: 扫描模板变量")
    print("=" * 60)
    
    all_variables = []  # List of (name, default, source_file)
    seen_vars = set()
    prompts_content = {}  # {path: content}
    
    for prompt_path in prompt_files:
        content = read_prompt_file(prompt_path)
        prompts_content[prompt_path] = content
        
        variables = extract_variables(content)
        for var_name, default_value in variables:
            if var_name not in seen_vars:
                all_variables.append((var_name, default_value, prompt_path.name))
                seen_vars.add(var_name)
    
    if all_variables:
        print(f"\n发现 {len(all_variables)} 个变量：")
        for var_name, default_value, source in all_variables:
            default_str = f" (默认: {default_value})" if default_value else ""
            print(f"   • {var_name}{default_str} ← {source}")
        
        # 收集变量值
        var_list = [(name, default) for name, default, _ in all_variables]
        values = collect_variables(var_list)
    else:
        print("\n未发现模板变量，直接执行。")
        values = {}
    
    # === 阶段 2: 顺序执行 ===
    print("\n" + "=" * 60)
    print("阶段 2: 执行 Prompts")
    print("=" * 60)
    
    for idx, prompt_path in enumerate(prompt_files, 1):
        print(f"\n[{idx}/{total}] 📄 {prompt_path.name}")
        print("-" * 40)
        
        # 获取内容并填充模板
        content = prompts_content[prompt_path]
        if values:
            content = fill_template(content, values)
        
        # 检测是否为交互模式
        interactive = is_interactive_prompt(content)
        mode_str = "交互模式" if interactive else "非交互模式"
        
        print(f"   文件大小: {len(content)} 字符")
        print(f"   执行模式: {mode_str}")
        
        # 执行
        if interactive:
            exit_code = execute_claude_code_interactive(content, project_dir)
        else:
            exit_code = execute_claude_code(content, project_dir)
        
        # 检查结果
        if exit_code != 0:
            print("\n" + "=" * 60)
            print(f"❌ 执行失败: {prompt_path.name} (exit code: {exit_code})")
            print(f"   已完成: {idx-1}/{total}")
            print(f"   未执行: {total-idx} 个文件")
            sys.exit(exit_code)
        
        print(f"   ✅ 完成")
    
    # 全部成功
    print("\n" + "=" * 60)
    print(f"✅ 全部完成 ({total}/{total})")
    sys.exit(0)


def main():
    parser = argparse.ArgumentParser(
        description="Claude Code Agent - 自动化执行 Claude Code Prompt",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 单个文件
  python agent.py run ./01-init.md --project ~/voice-platform
  
  # 多个文件（按文件名排序执行）
  python agent.py run ./01.md ./02.md ./03.md --project ~/voice-platform
  
  # 通配符
  python agent.py run ./prompts/*.md --project ~/voice-platform

模板变量:
  在 Prompt 文件中使用 {{variable}} 或 {{variable:default}} 格式。
  Agent 会在执行前一次性收集所有变量，然后全自动执行。
        """
    )
    
    subparsers = parser.add_subparsers(dest='command', help='可用命令')
    
    # run 子命令
    run_parser = subparsers.add_parser('run', help='执行 Prompt 文件')
    run_parser.add_argument('prompt_files', nargs='+', help='Prompt 文件路径，支持多个文件')
    run_parser.add_argument('--project', '-p', required=True, help='目标项目目录')
    run_parser.set_defaults(func=run_command)
    
    # 解析参数
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    args.func(args)


if __name__ == '__main__':
    main()
