// Start a process under a REDUCED token, and read a process's real token state.
// Generic: identical in every loop (from the innovation-loop kit). Loaded by lib.ps1 (Add-Type). No secrets.
//
// WHY: Windows does not drop admin rights for scheduled tasks of an admin account. RunLevel Limited with an
// S4U or Password logon still yields a FULL token (TokenElevation=1, TokenElevationType=Default): no UAC
// split token is created for non-interactive logons. run-loop.ps1 therefore drops rights itself before
// starting the claude session, and fails closed if it cannot.
//
// HOW (the stricter of the two launchers used on server-pc, chosen for the kit):
//  - CreateRestrictedToken(own token, LUA_TOKEN | DISABLE_MAX_PRIVILEGE, deny-only: Administrators and
//    S-1-5-114 "local account and member of Administrators"): the UAC filter. Admin groups deny-only,
//    every privilege except SeChangeNotify removed, AND the elevation flag cleared (TokenElevation=0).
//    The alternative, SAFER SaferComputeTokenFromLevel(NORMALUSER) (cardlens's first launcher), gives the
//    same groups/privileges but keeps TokenElevation=1, so "is it elevated?" cannot serve as a fail-closed
//    readback with it; with LUA_TOKEN it can, on top of the group/integrity/privilege checks.
//  - integrity pinned to Medium (S-1-16-8192); otherwise the child keeps the parent's High label.
//  - token owner = the user and default DACL = user + SYSTEM (+ Administrators, so the elevated parent can
//    still kill the tree; the child cannot use that ACE, it holds Administrators deny-only). Without this
//    the child inherits owner=Administrators and an Administrators+SYSTEM default DACL, cannot open its own
//    process/token, and dies at startup (0xC0000142 / access denied; measured on server-pc).
//  - CreateProcessAsUser (allowed without SeAssignPrimaryToken: the token is a filtered copy of the
//    caller's own) with CREATE_SUSPENDED; the CHILD's real token is read back and checked BEFORE the
//    thread is resumed. Anything not reduced is terminated before it executes a single instruction.
//  - Reduced = TokenElevation 0 AND Administrators deny-only/absent AND integrity <= Medium AND only
//    standard-user privileges. lib.ps1 Test-TokenReduced re-checks the same on the logged state string.
//  stdin/stdout/stderr are redirected to files through inheritable handles.
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;

public static class InnovationLoopLowRights
{
    const int TokenUser = 1, TokenGroups = 2, TokenPrivileges = 3, TokenOwner = 4, TokenDefaultDacl = 6;
    const int TokenElevationType = 18, TokenElevation = 20, TokenIntegrityLevel = 25;
    const uint SE_GROUP_ENABLED = 0x4, SE_GROUP_USE_FOR_DENY_ONLY = 0x10, SE_GROUP_INTEGRITY = 0x20;
    const uint TOKEN_ASSIGN_PRIMARY = 0x1, TOKEN_DUPLICATE = 0x2, TOKEN_QUERY = 0x8, TOKEN_ADJUST_DEFAULT = 0x80;
    const uint DISABLE_MAX_PRIVILEGE = 0x1, LUA_TOKEN = 0x4;
    const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000, FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2;
    const uint OPEN_EXISTING = 3, CREATE_ALWAYS = 2, FILE_ATTRIBUTE_NORMAL = 0x80;
    const uint STARTF_USESTDHANDLES = 0x100, STARTF_USESHOWWINDOW = 1;
    const uint CREATE_SUSPENDED = 0x4, CREATE_NO_WINDOW = 0x08000000;
    const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    const string ADMINS = "S-1-5-32-544", MEDIUM = "S-1-16-8192";
    static readonly string[] StandardPrivileges = { "SeChangeNotifyPrivilege", "SeShutdownPrivilege", "SeUndockPrivilege", "SeIncreaseWorkingSetPrivilege", "SeTimeZonePrivilege" };

    [StructLayout(LayoutKind.Sequential)] struct SECURITY_ATTRIBUTES { public int nLength; public IntPtr lpSecurityDescriptor; public bool bInheritHandle; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public uint dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public uint dwProcessId, dwThreadId; }
    [StructLayout(LayoutKind.Sequential)] struct SID_AND_ATTRIBUTES { public IntPtr Sid; public uint Attributes; }

    [DllImport("advapi32.dll", SetLastError = true)] static extern bool CreateRestrictedToken(IntPtr token, uint flags, uint disableCount, IntPtr disable, uint deleteCount, IntPtr delete, uint restrictCount, IntPtr restrict, out IntPtr newToken);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool ConvertStringSidToSid(string s, out IntPtr sid);
    [DllImport("advapi32.dll")] static extern int GetLengthSid(IntPtr sid);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool SetTokenInformation(IntPtr h, int cls, IntPtr info, int len);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool GetTokenInformation(IntPtr h, int cls, IntPtr info, int len, out int ret);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr p, uint access, out IntPtr tok);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessAsUser(IntPtr tok, string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool LookupPrivilegeName(string sys, IntPtr luid, StringBuilder name, ref int len);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateFile(string name, uint access, uint share, ref SECURITY_ATTRIBUTES sa, uint disp, uint attrs, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateProcess(IntPtr h, uint code);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint ResumeThread(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);

    static Win32Exception Fail(string what) { int e = Marshal.GetLastWin32Error(); return new Win32Exception(e, what + " failed: error " + e); }

    static IntPtr OpenInheritable(string path, bool write) {
        var sa = new SECURITY_ATTRIBUTES { nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES)), bInheritHandle = true };
        IntPtr h = write
            ? CreateFile(path, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, ref sa, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero)
            : CreateFile(path, GENERIC_READ, FILE_SHARE_READ, ref sa, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
        if (h == new IntPtr(-1)) throw Fail("CreateFile " + path);
        return h;
    }

    static IntPtr Query(IntPtr tok, int cls) {
        int len; GetTokenInformation(tok, cls, IntPtr.Zero, 0, out len);
        if (len <= 0) len = 16;
        IntPtr buf = Marshal.AllocHGlobal(len);
        if (!GetTokenInformation(tok, cls, buf, len, out len)) { Marshal.FreeHGlobal(buf); throw Fail("GetTokenInformation(" + cls + ")"); }
        return buf;
    }

    // "elevated=<0|1> elevationType=<1|2|3> integrity=0x<rid> adminEnabled=<True|False> adminState=<enabled|deny-only|disabled|absent> privileges=<a,b>"
    static string Describe(IntPtr tok) {
        IntPtr b = Query(tok, TokenElevation); int elevated = Marshal.ReadInt32(b); Marshal.FreeHGlobal(b);
        b = Query(tok, TokenElevationType); int type = Marshal.ReadInt32(b); Marshal.FreeHGlobal(b);
        int rid = -1;
        b = Query(tok, TokenIntegrityLevel);
        try { IntPtr sid = Marshal.ReadIntPtr(b); int sub = Marshal.ReadByte(sid, 1); rid = Marshal.ReadInt32(sid, 8 + 4 * (sub - 1)); }
        finally { Marshal.FreeHGlobal(b); }
        string admin = "absent";
        b = Query(tok, TokenGroups);
        try {
            int count = Marshal.ReadInt32(b);
            int size = Marshal.SizeOf(typeof(SID_AND_ATTRIBUTES));
            long first = b.ToInt64() + IntPtr.Size;   // DWORD GroupCount padded to pointer alignment
            for (int i = 0; i < count; i++) {
                var g = (SID_AND_ATTRIBUTES)Marshal.PtrToStructure(new IntPtr(first + (long)i * size), typeof(SID_AND_ATTRIBUTES));
                if (new SecurityIdentifier(g.Sid).Value != ADMINS) continue;
                if ((g.Attributes & SE_GROUP_USE_FOR_DENY_ONLY) != 0) admin = "deny-only";
                else if ((g.Attributes & SE_GROUP_ENABLED) != 0) admin = "enabled";
                else admin = "disabled";
            }
        } finally { Marshal.FreeHGlobal(b); }
        var privs = new System.Collections.Generic.List<string>();
        b = Query(tok, TokenPrivileges);
        try {
            int count = Marshal.ReadInt32(b);
            for (int i = 0; i < count; i++) {
                IntPtr luid = new IntPtr(b.ToInt64() + 4 + i * 12);
                var sb = new StringBuilder(64); int len = 64;
                if (LookupPrivilegeName(null, luid, sb, ref len)) privs.Add(sb.ToString());
            }
        } finally { Marshal.FreeHGlobal(b); }
        return "elevated=" + elevated + " elevationType=" + type + " integrity=0x" + rid.ToString("x") + " adminEnabled=" + (admin == "enabled")
            + " adminState=" + admin + " privileges=" + string.Join(",", privs.ToArray());
    }

    public static bool IsReduced(string state) {
        if (state.IndexOf("elevated=0 ", StringComparison.Ordinal) != 0) return false;
        if (state.IndexOf("adminState=deny-only", StringComparison.Ordinal) < 0 && state.IndexOf("adminState=absent", StringComparison.Ordinal) < 0) return false;
        if (state.IndexOf("integrity=0x2000 ", StringComparison.Ordinal) < 0 && state.IndexOf("integrity=0x1000 ", StringComparison.Ordinal) < 0) return false;
        int p = state.IndexOf("privileges=", StringComparison.Ordinal);
        if (p < 0) return false;
        foreach (string pr in state.Substring(p + 11).Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries))
            if (Array.IndexOf(StandardPrivileges, pr.Trim()) < 0) return false;
        return true;
    }

    // Filtered (UAC/LUA) Medium-integrity primary token derived from this process's token. Caller closes it.
    public static IntPtr CreateReducedToken() {
        IntPtr own, tok;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ASSIGN_PRIMARY | TOKEN_ADJUST_DEFAULT, out own)) throw Fail("OpenProcessToken(self)");
        string[] adminSids = { ADMINS, "S-1-5-114" };
        IntPtr[] psids = new IntPtr[adminSids.Length];
        int saSize = Marshal.SizeOf(typeof(SID_AND_ATTRIBUTES));
        IntPtr arr = Marshal.AllocHGlobal(saSize * adminSids.Length);
        try {
            for (int i = 0; i < adminSids.Length; i++) {
                if (!ConvertStringSidToSid(adminSids[i], out psids[i])) throw Fail("ConvertStringSidToSid");
                Marshal.StructureToPtr(new SID_AND_ATTRIBUTES { Sid = psids[i], Attributes = 0 }, new IntPtr(arr.ToInt64() + (long)i * saSize), false);
            }
            if (!CreateRestrictedToken(own, LUA_TOKEN | DISABLE_MAX_PRIVILEGE, (uint)adminSids.Length, arr, 0, IntPtr.Zero, 0, IntPtr.Zero, out tok)) throw Fail("CreateRestrictedToken");
        } finally {
            Marshal.FreeHGlobal(arr);
            foreach (IntPtr p in psids) if (p != IntPtr.Zero) LocalFree(p);
            CloseHandle(own);
        }
        try {
            IntPtr sid;
            if (!ConvertStringSidToSid(MEDIUM, out sid)) throw Fail("ConvertStringSidToSid");
            int size = saSize + GetLengthSid(sid);
            IntPtr tml = Marshal.AllocHGlobal(size);
            try {
                Marshal.StructureToPtr(new SID_AND_ATTRIBUTES { Sid = sid, Attributes = SE_GROUP_INTEGRITY }, tml, false);
                if (!SetTokenInformation(tok, TokenIntegrityLevel, tml, size)) throw Fail("SetTokenInformation(integrity)");
            } finally { Marshal.FreeHGlobal(tml); LocalFree(sid); }

            IntPtr ub = Query(tok, TokenUser);
            IntPtr ownerBuf = IntPtr.Zero, dacl = IntPtr.Zero, tdd = IntPtr.Zero;
            try {
                IntPtr userSid = Marshal.ReadIntPtr(ub);
                var user = new SecurityIdentifier(userSid);
                ownerBuf = Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(ownerBuf, userSid);
                if (!SetTokenInformation(tok, TokenOwner, ownerBuf, IntPtr.Size)) throw Fail("SetTokenInformation(owner)");
                var acl = new RawAcl(GenericAcl.AclRevision, 3);
                int ga = unchecked((int)0x10000000);   // GENERIC_ALL
                acl.InsertAce(0, new CommonAce(AceFlags.None, AceQualifier.AccessAllowed, ga, user, false, null));
                acl.InsertAce(1, new CommonAce(AceFlags.None, AceQualifier.AccessAllowed, ga, new SecurityIdentifier("S-1-5-18"), false, null));
                acl.InsertAce(2, new CommonAce(AceFlags.None, AceQualifier.AccessAllowed, ga, new SecurityIdentifier(ADMINS), false, null));
                byte[] bin = new byte[acl.BinaryLength]; acl.GetBinaryForm(bin, 0);
                dacl = Marshal.AllocHGlobal(bin.Length); Marshal.Copy(bin, 0, dacl, bin.Length);
                tdd = Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(tdd, dacl);
                if (!SetTokenInformation(tok, TokenDefaultDacl, tdd, IntPtr.Size)) throw Fail("SetTokenInformation(default DACL)");
            } finally {
                Marshal.FreeHGlobal(ub);
                if (ownerBuf != IntPtr.Zero) Marshal.FreeHGlobal(ownerBuf);
                if (tdd != IntPtr.Zero) Marshal.FreeHGlobal(tdd);
                if (dacl != IntPtr.Zero) Marshal.FreeHGlobal(dacl);
            }
            string st = Describe(tok);
            if (!IsReduced(st)) throw new InvalidOperationException("computed token is not reduced: " + st);
            return tok;
        } catch { CloseHandle(tok); throw; }
    }

    // Returns "pid|processHandle|method". The child is created SUSPENDED, its own token is read back and must be
    // reduced, and only then is it resumed; otherwise it is terminated before running and this throws.
    // The caller waits with Wait(handle, ms) and then CloseProcess(handle).
    public static string Start(string app, string commandLine, string cwd, string stdinPath, string stdoutPath, string stderrPath) {
        IntPtr tok = CreateReducedToken();
        IntPtr hIn = IntPtr.Zero, hOut = IntPtr.Zero, hErr = IntPtr.Zero;
        PROCESS_INFORMATION pi;
        try {
            hIn = !string.IsNullOrEmpty(stdinPath) ? OpenInheritable(stdinPath, false) : OpenInheritable("NUL", false);
            hOut = OpenInheritable(stdoutPath, true);
            hErr = OpenInheritable(stderrPath, true);
            var si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
            si.wShowWindow = 0;
            si.hStdInput = hIn; si.hStdOutput = hOut; si.hStdError = hErr;
            if (!CreateProcessAsUser(tok, app, new StringBuilder(commandLine), IntPtr.Zero, IntPtr.Zero, true, CREATE_SUSPENDED | CREATE_NO_WINDOW, IntPtr.Zero, cwd, ref si, out pi))
                throw Fail("CreateProcessAsUser");
        } finally {
            if (hIn != IntPtr.Zero) CloseHandle(hIn);
            if (hOut != IntPtr.Zero) CloseHandle(hOut);
            if (hErr != IntPtr.Zero) CloseHandle(hErr);
            CloseHandle(tok);
        }
        string child;
        try {
            IntPtr ct;
            if (!OpenProcessToken(pi.hProcess, TOKEN_QUERY, out ct)) throw Fail("OpenProcessToken(child)");
            try { child = Describe(ct); } finally { CloseHandle(ct); }
        } catch { TerminateProcess(pi.hProcess, 1); CloseHandle(pi.hThread); CloseHandle(pi.hProcess); throw; }
        if (!IsReduced(child)) {
            TerminateProcess(pi.hProcess, 1); CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
            throw new InvalidOperationException("child token is not reduced (" + child + "); terminated it before it ran");
        }
        ResumeThread(pi.hThread);
        CloseHandle(pi.hThread);
        return pi.dwProcessId + "|" + pi.hProcess.ToInt64() + "|CreateRestrictedToken(LUA)+CreateProcessAsUser(suspended, checked)";
    }

    // Token state of any process we can open (0 = this process). Same format as Describe.
    public static string Inspect(int pid) {
        IntPtr p = pid == 0 ? GetCurrentProcess() : OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, (uint)pid);
        if (p == IntPtr.Zero) throw Fail("OpenProcess " + pid);
        IntPtr tok;
        if (!OpenProcessToken(p, TOKEN_QUERY, out tok)) { if (pid != 0) CloseHandle(p); throw Fail("OpenProcessToken " + pid); }
        try { return Describe(tok); } finally { CloseHandle(tok); if (pid != 0) CloseHandle(p); }
    }

    // Wait on the handle Start returned; exit code, or -1 if it did not finish within ms (NOT killed here).
    public static long Wait(long handle, uint ms) {
        IntPtr p = new IntPtr(handle);
        if (WaitForSingleObject(p, ms) != 0) return -1;
        uint code; GetExitCodeProcess(p, out code); return code;
    }

    public static void CloseProcess(long handle) { CloseHandle(new IntPtr(handle)); }
}
