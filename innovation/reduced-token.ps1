# Launch a process under a REDUCED token: a UAC-style filtered (LUA) copy of this process's own token, admin
# groups deny-only, every privilege but SeChangeNotify removed (the same rights as SAFER "Basic User", i.e.
# `runas /trustlevel:0x20000`), elevation flag cleared, integrity pinned to Medium.
# Dot-source it:  . "$PSScriptRoot\reduced-token.ps1"
#
# Why: the InnovationLoop task runs as an admin account in a non-interactive logon (S4U or Password). Windows
# creates no UAC split token for those logons, so the task's RunLevel Limited has no effect and the runner gets a
# full admin token (TokenElevation=1, TokenElevationType=Default). run-loop.ps1 therefore drops rights itself
# before starting claude: everything the session runs inherits the reduced token.
#
# What the reduced token is: the same user (same profile, HKCU, ~\.claude, ~\.ssh, gh's hosts.yml), with
# BUILTIN\Administrators and the other admin SIDs turned into deny-only groups, admin privileges removed, and
# Medium integrity. It fails closed: the token and then the actual child process token are checked, and if
# either still reports elevation or an enabled Administrators group, the child is killed before it ever runs
# (it is created suspended) and an exception is thrown.
#
# PowerShell 5.1 compatible (Add-Type, C# 5). No secrets are read or printed.

if (-not ('InnovationLoop.ReducedToken' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;

namespace InnovationLoop {

public sealed class TokenState {
    public int Elevation;          // TokenElevation.TokenIsElevated
    public int ElevationType;      // 1 Default, 2 Full, 3 Limited
    public string Integrity;       // Low / Medium / High / System / S-1-16-x
    public string Administrators;  // enabled / deny-only / disabled / absent
    // reduced = not elevated, Administrators deny-only or absent (a merely disabled group could be re-enabled), at most Medium integrity
    public bool IsReduced { get { return Elevation == 0 && (Administrators == "deny-only" || Administrators == "absent") && (Integrity == "Medium" || Integrity == "Low"); } }
    public override string ToString() {
        return string.Format("TokenElevation={0} TokenElevationType={1} integrity={2} Administrators={3}",
            Elevation, ElevationType, Integrity, Administrators);
    }
}

public sealed class ReducedProcess : IDisposable {
    IntPtr hProcess;
    public int Id { get; private set; }
    public TokenState Token { get; private set; }
    internal ReducedProcess(IntPtr h, int id, TokenState t) { hProcess = h; Id = id; Token = t; }
    // true if the process exited within ms (-1 = wait forever)
    public bool WaitForExit(int ms) {
        uint r = Native.WaitForSingleObject(hProcess, ms < 0 ? 0xFFFFFFFF : (uint)ms);
        if (r == 0) return true;
        if (r == 0x102) return false;
        throw ReducedToken.Fail(Marshal.GetLastWin32Error(), "WaitForSingleObject");
    }
    public int ExitCode {
        get {
            uint c;
            if (!Native.GetExitCodeProcess(hProcess, out c)) throw ReducedToken.Fail(Marshal.GetLastWin32Error(), "GetExitCodeProcess");
            return unchecked((int)c);
        }
    }
    public void Kill() { Native.TerminateProcess(hProcess, 1); }
    public void Dispose() { if (hProcess != IntPtr.Zero) { Native.CloseHandle(hProcess); hProcess = IntPtr.Zero; } }
}

internal static class Native {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX; public int dwY; public int dwXSize; public int dwYSize; public int dwXCountChars; public int dwYCountChars;
        public int dwFillAttribute; public int dwFlags; public short wShowWindow; public short cbReserved2; public IntPtr lpReserved2;
        public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION { public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId; }
    [StructLayout(LayoutKind.Sequential)]
    public struct SID_AND_ATTRIBUTES { public IntPtr Sid; public uint Attributes; }

    [DllImport("advapi32.dll", SetLastError = true)] public static extern bool CreateRestrictedToken(IntPtr token, uint flags, uint disableCount, IntPtr disable,
        uint deleteCount, IntPtr delete, uint restrictCount, IntPtr restrict, out IntPtr newToken);
    [DllImport("advapi32.dll", SetLastError = true)] public static extern bool GetTokenInformation(IntPtr token, int cls, IntPtr info, int len, out int retLen);
    [DllImport("advapi32.dll", SetLastError = true)] public static extern bool SetTokenInformation(IntPtr token, int cls, IntPtr info, int len);
    [DllImport("advapi32.dll", SetLastError = true)] public static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool ConvertStringSidToSid(string sid, out IntPtr psid);
    [DllImport("advapi32.dll", SetLastError = true)] public static extern int GetLengthSid(IntPtr psid);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CreateProcessAsUser(IntPtr token, string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit,
        uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr LocalFree(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern uint ResumeThread(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool TerminateProcess(IntPtr h, uint code);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetHandleInformation(IntPtr h, uint mask, uint flags);
    [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
}

public static class ReducedToken {
    const int TokenUser = 1, TokenGroups = 2, TokenOwner = 4, TokenDefaultDacl = 6, TokenElevationType = 18, TokenElevation = 20, TokenIntegrityLevel = 25;
    const uint SE_GROUP_ENABLED = 0x4, SE_GROUP_USE_FOR_DENY_ONLY = 0x10, SE_GROUP_INTEGRITY = 0x20;
    const uint TOKEN_ASSIGN_PRIMARY = 0x1, TOKEN_DUPLICATE = 0x2, TOKEN_QUERY = 0x8, TOKEN_ADJUST_DEFAULT = 0x80, DISABLE_MAX_PRIVILEGE = 0x1, LUA_TOKEN = 0x4;
    const uint CREATE_SUSPENDED = 0x4, CREATE_NO_WINDOW = 0x08000000;
    const int STARTF_USESTDHANDLES = 0x100;
    const string ADMINS = "S-1-5-32-544", MEDIUM = "S-1-16-8192";

    internal static Win32Exception Fail(int code, string what) {
        return new Win32Exception(code, what + " failed: error " + code + " (" + new Win32Exception(code).Message + ")");
    }

    static IntPtr Query(IntPtr token, int cls) {
        int len;
        Native.GetTokenInformation(token, cls, IntPtr.Zero, 0, out len);
        if (len <= 0) len = 16;
        IntPtr buf = Marshal.AllocHGlobal(len);
        if (!Native.GetTokenInformation(token, cls, buf, len, out len)) {
            int e = Marshal.GetLastWin32Error(); Marshal.FreeHGlobal(buf);
            throw Fail(e, "GetTokenInformation(" + cls + ")");
        }
        return buf;
    }

    public static TokenState Read(IntPtr token) {
        TokenState s = new TokenState();
        IntPtr b = Query(token, TokenElevation); s.Elevation = Marshal.ReadInt32(b); Marshal.FreeHGlobal(b);
        b = Query(token, TokenElevationType); s.ElevationType = Marshal.ReadInt32(b); Marshal.FreeHGlobal(b);
        b = Query(token, TokenIntegrityLevel);
        try {
            string il = new SecurityIdentifier(Marshal.ReadIntPtr(b)).Value;
            switch (il) {
                case "S-1-16-4096": s.Integrity = "Low"; break;
                case "S-1-16-8192": s.Integrity = "Medium"; break;
                case "S-1-16-8448": s.Integrity = "MediumPlus"; break;
                case "S-1-16-12288": s.Integrity = "High"; break;
                case "S-1-16-16384": s.Integrity = "System"; break;
                default: s.Integrity = il; break;
            }
        } finally { Marshal.FreeHGlobal(b); }
        b = Query(token, TokenGroups);
        try {
            s.Administrators = "absent";
            int count = Marshal.ReadInt32(b);
            int size = Marshal.SizeOf(typeof(Native.SID_AND_ATTRIBUTES));
            long first = b.ToInt64() + IntPtr.Size;   // DWORD GroupCount, padded to pointer alignment
            for (int i = 0; i < count; i++) {
                Native.SID_AND_ATTRIBUTES g = (Native.SID_AND_ATTRIBUTES)Marshal.PtrToStructure(new IntPtr(first + (long)i * size), typeof(Native.SID_AND_ATTRIBUTES));
                if (new SecurityIdentifier(g.Sid).Value != ADMINS) continue;
                if ((g.Attributes & SE_GROUP_USE_FOR_DENY_ONLY) != 0) s.Administrators = "deny-only";
                else if ((g.Attributes & SE_GROUP_ENABLED) != 0) s.Administrators = "enabled";
                else s.Administrators = "disabled";
            }
        } finally { Marshal.FreeHGlobal(b); }
        return s;
    }

    public static TokenState Current() {
        IntPtr t;
        if (!Native.OpenProcessToken(Native.GetCurrentProcess(), TOKEN_QUERY, out t)) throw Fail(Marshal.GetLastWin32Error(), "OpenProcessToken(self)");
        try { return Read(t); } finally { Native.CloseHandle(t); }
    }

    public static TokenState OfProcess(IntPtr hProcess) {
        IntPtr t;
        if (!Native.OpenProcessToken(hProcess, TOKEN_QUERY, out t)) throw Fail(Marshal.GetLastWin32Error(), "OpenProcessToken(child)");
        try { return Read(t); } finally { Native.CloseHandle(t); }
    }

    static IntPtr CreateToken() {
        // A filtered copy of this process's own primary token (so CreateProcessAsUser needs no
        // SeAssignPrimaryTokenPrivilege):
        //   LUA_TOKEN             - filter it the way UAC filters an admin's token: admin groups deny-only and the
        //                           elevation flag cleared (TokenElevation=0)
        //   DISABLE_MAX_PRIVILEGE - remove every privilege except SeChangeNotifyPrivilege (as SAFER Basic User)
        //   disabled SIDs         - BUILTIN\Administrators and "Local account and member of Administrators"
        //                           explicitly deny-only as well
        // Why not SAFER's SaferComputeTokenFromLevel (what `runas /trustlevel:0x20000` uses): measured on this box,
        // its token has the same groups and privileges but keeps TokenElevation=1, and re-filtering it makes it a
        // grandchild of our token, which CreateProcessAsUser then refuses without SeAssignPrimaryTokenPrivilege.
        IntPtr own, token;
        if (!Native.OpenProcessToken(Native.GetCurrentProcess(), TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ASSIGN_PRIMARY | TOKEN_ADJUST_DEFAULT, out own))
            throw Fail(Marshal.GetLastWin32Error(), "OpenProcessToken(self)");
        string[] adminSids = { ADMINS, "S-1-5-114" };
        IntPtr[] psids = new IntPtr[adminSids.Length];
        int saSize = Marshal.SizeOf(typeof(Native.SID_AND_ATTRIBUTES));
        IntPtr arr = Marshal.AllocHGlobal(saSize * adminSids.Length);
        try {
            for (int i = 0; i < adminSids.Length; i++) {
                if (!Native.ConvertStringSidToSid(adminSids[i], out psids[i])) throw Fail(Marshal.GetLastWin32Error(), "ConvertStringSidToSid");
                Native.SID_AND_ATTRIBUTES sa = new Native.SID_AND_ATTRIBUTES(); sa.Sid = psids[i]; sa.Attributes = 0;
                Marshal.StructureToPtr(sa, new IntPtr(arr.ToInt64() + (long)i * saSize), false);
            }
            if (!Native.CreateRestrictedToken(own, LUA_TOKEN | DISABLE_MAX_PRIVILEGE, (uint)adminSids.Length, arr, 0, IntPtr.Zero, 0, IntPtr.Zero, out token))
                throw Fail(Marshal.GetLastWin32Error(), "CreateRestrictedToken");
        } finally {
            Marshal.FreeHGlobal(arr);
            foreach (IntPtr p in psids) if (p != IntPtr.Zero) Native.LocalFree(p);
            Native.CloseHandle(own);
        }
        // Pin the integrity level to Medium (lowering is always allowed). Without this the token can keep the
        // parent's High label, which would let the child write to High-labelled objects.
        IntPtr sid;
        if (!Native.ConvertStringSidToSid(MEDIUM, out sid)) { Native.CloseHandle(token); throw Fail(Marshal.GetLastWin32Error(), "ConvertStringSidToSid"); }
        int tmlSize = Marshal.SizeOf(typeof(Native.SID_AND_ATTRIBUTES));
        IntPtr tml = Marshal.AllocHGlobal(tmlSize + Native.GetLengthSid(sid));
        try {
            Native.SID_AND_ATTRIBUTES label = new Native.SID_AND_ATTRIBUTES(); label.Sid = sid; label.Attributes = SE_GROUP_INTEGRITY;
            Marshal.StructureToPtr(label, tml, false);
            if (!Native.SetTokenInformation(token, TokenIntegrityLevel, tml, tmlSize + Native.GetLengthSid(sid))) {
                int e = Marshal.GetLastWin32Error(); Native.CloseHandle(token);
                throw Fail(e, "SetTokenInformation(TokenIntegrityLevel)");
            }
        } finally { Marshal.FreeHGlobal(tml); Native.LocalFree(sid); }
        // Owner and default DACL. An elevated token's defaults are owner=Administrators and a default DACL of
        // Administrators+SYSTEM only. Inherited unchanged, the child could not open its own process or token
        // (Administrators is deny-only now), and fails at startup (0xC0000142 / "Access is denied"; measured).
        // Use what a standard user's token has: owner = the user, default DACL = user + SYSTEM full control.
        // Administrators also gets full control so the elevated runner can still kill the tree on timeout; the
        // child itself cannot use that entry (deny-only).
        IntPtr ub = Query(token, TokenUser);
        IntPtr own2 = IntPtr.Zero, dacl = IntPtr.Zero, tdd = IntPtr.Zero;
        try {
            IntPtr userSid = Marshal.ReadIntPtr(ub);
            SecurityIdentifier user = new SecurityIdentifier(userSid);
            own2 = Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(own2, userSid);
            if (!Native.SetTokenInformation(token, TokenOwner, own2, IntPtr.Size)) {
                int e = Marshal.GetLastWin32Error(); Native.CloseHandle(token); throw Fail(e, "SetTokenInformation(TokenOwner)");
            }
            RawAcl acl = new RawAcl(GenericAcl.AclRevision, 3);
            int ga = unchecked((int)0x10000000);   // GENERIC_ALL
            acl.InsertAce(0, new CommonAce(AceFlags.None, AceQualifier.AccessAllowed, ga, user, false, null));
            acl.InsertAce(1, new CommonAce(AceFlags.None, AceQualifier.AccessAllowed, ga, new SecurityIdentifier("S-1-5-18"), false, null));
            acl.InsertAce(2, new CommonAce(AceFlags.None, AceQualifier.AccessAllowed, ga, new SecurityIdentifier(ADMINS), false, null));
            byte[] bin = new byte[acl.BinaryLength]; acl.GetBinaryForm(bin, 0);
            dacl = Marshal.AllocHGlobal(bin.Length); Marshal.Copy(bin, 0, dacl, bin.Length);
            tdd = Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(tdd, dacl);
            if (!Native.SetTokenInformation(token, TokenDefaultDacl, tdd, IntPtr.Size)) {
                int e = Marshal.GetLastWin32Error(); Native.CloseHandle(token); throw Fail(e, "SetTokenInformation(TokenDefaultDacl)");
            }
        } finally {
            Marshal.FreeHGlobal(ub);
            if (own2 != IntPtr.Zero) Marshal.FreeHGlobal(own2);
            if (tdd != IntPtr.Zero) Marshal.FreeHGlobal(tdd);
            if (dacl != IntPtr.Zero) Marshal.FreeHGlobal(dacl);
        }
        TokenState st = Read(token);
        if (!st.IsReduced || st.Integrity != "Medium") { Native.CloseHandle(token); throw new InvalidOperationException("computed token is not reduced: " + st); }
        return token;
    }

    static FileStream Inheritable(FileStream fs) {
        if (!Native.SetHandleInformation(fs.SafeFileHandle.DangerousGetHandle(), 1, 1))
            throw Fail(Marshal.GetLastWin32Error(), "SetHandleInformation");
        return fs;
    }

    // Start `commandLine` (which must begin with the quoted program path) under the reduced token, stdin from
    // stdinPath (or none), stdout/stderr to new files. The child inherits this process's environment and is
    // created suspended; it is resumed only after its own token has been read back and checked.
    public static ReducedProcess Start(string app, string commandLine, string workDir, string stdinPath, string stdoutPath, string stderrPath) {
        IntPtr token = CreateToken();
        FileStream fin = null, fout = null, ferr = null;
        Native.PROCESS_INFORMATION pi = new Native.PROCESS_INFORMATION();
        try {
            if (!string.IsNullOrEmpty(stdinPath)) fin = Inheritable(new FileStream(stdinPath, FileMode.Open, FileAccess.Read, FileShare.Read));
            fout = Inheritable(new FileStream(stdoutPath, FileMode.Create, FileAccess.Write, FileShare.ReadWrite));
            ferr = Inheritable(new FileStream(stderrPath, FileMode.Create, FileAccess.Write, FileShare.ReadWrite));
            Native.STARTUPINFO si = new Native.STARTUPINFO();
            si.cb = Marshal.SizeOf(typeof(Native.STARTUPINFO));
            si.dwFlags = STARTF_USESTDHANDLES;
            si.hStdInput = fin == null ? IntPtr.Zero : fin.SafeFileHandle.DangerousGetHandle();
            si.hStdOutput = fout.SafeFileHandle.DangerousGetHandle();
            si.hStdError = ferr.SafeFileHandle.DangerousGetHandle();
            StringBuilder cmd = new StringBuilder(commandLine);
            if (!Native.CreateProcessAsUser(token, app, cmd, IntPtr.Zero, IntPtr.Zero, true, CREATE_SUSPENDED | CREATE_NO_WINDOW,
                    IntPtr.Zero, workDir, ref si, out pi))
                throw Fail(Marshal.GetLastWin32Error(), "CreateProcessAsUser");
        } finally {
            Native.CloseHandle(token);
            if (fin != null) fin.Dispose();
            if (fout != null) fout.Dispose();
            if (ferr != null) ferr.Dispose();
        }
        TokenState child;
        try { child = OfProcess(pi.hProcess); }
        catch { Native.TerminateProcess(pi.hProcess, 1); Native.CloseHandle(pi.hThread); Native.CloseHandle(pi.hProcess); throw; }
        if (!child.IsReduced) {
            Native.TerminateProcess(pi.hProcess, 1); Native.CloseHandle(pi.hThread); Native.CloseHandle(pi.hProcess);
            throw new InvalidOperationException("child token is not reduced (" + child + "); killed it before it ran");
        }
        Native.ResumeThread(pi.hThread);
        Native.CloseHandle(pi.hThread);
        return new ReducedProcess(pi.hProcess, pi.dwProcessId, child);
    }
}
}
'@
}

function Get-TokenState { [InnovationLoop.ReducedToken]::Current() }

# Start a native exe under the reduced token. $ArgumentString is appended verbatim to the quoted exe path.
# Returns an InnovationLoop.ReducedProcess (Id, Token, WaitForExit(ms), ExitCode, Kill(), Dispose()).
# Throws (never falls back to the caller's token) if the rights cannot be dropped.
function Start-ReducedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$ArgumentString = '',
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [string]$StdinPath = '',
        [Parameter(Mandatory)][string]$StdoutPath,
        [Parameter(Mandatory)][string]$StderrPath
    )
    $cmd = ('"{0}" {1}' -f $FilePath, $ArgumentString).TrimEnd()
    return [InnovationLoop.ReducedToken]::Start($FilePath, $cmd, $WorkingDirectory, $StdinPath, $StdoutPath, $StderrPath)
}

# Run a native exe under the reduced token and wait. Returns @{ Code; Output; Token }.
function Invoke-ReducedNative {
    param([Parameter(Mandatory)][string]$FilePath, [string]$ArgumentString = '', [string]$WorkingDirectory = (Get-Location).Path,
          [int]$TimeoutSec = 600)
    $tmp = [IO.Path]::GetTempFileName(); $tmpErr = [IO.Path]::GetTempFileName()
    try {
        $p = Start-ReducedProcess -FilePath $FilePath -ArgumentString $ArgumentString -WorkingDirectory $WorkingDirectory -StdoutPath $tmp -StderrPath $tmpErr
        try {
            if (-not $p.WaitForExit($TimeoutSec * 1000)) {
                & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null
                $p.Kill()
                throw "timed out after $TimeoutSec s: $FilePath $ArgumentString"
            }
            $out = @([IO.File]::ReadAllLines($tmp)) + @([IO.File]::ReadAllLines($tmpErr))
            return @{ Code = $p.ExitCode; Output = $out; Token = $p.Token }
        } finally { $p.Dispose() }
    } finally { Remove-Item -LiteralPath $tmp, $tmpErr -Force -ErrorAction SilentlyContinue }
}
