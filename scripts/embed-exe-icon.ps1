# Embeds a multi-size .ico into a PE as RT_GROUP_ICON / RT_ICON (MAINICON).
# Usage: powershell -File scripts/embed-exe-icon.ps1 -Exe path\to\app.exe -Ico path\to\app.ico

param(
  [Parameter(Mandatory = $true)][string]$Exe,
  [Parameter(Mandatory = $true)][string]$Ico
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $Exe)) { throw "Exe not found: $Exe" }
if (-not (Test-Path -LiteralPath $Ico)) { throw "Ico not found: $Ico" }

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;

public static class PeIconEmbedder {
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  static extern IntPtr BeginUpdateResource(string pFileName, bool bDeleteExistingResources);

  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool UpdateResource(IntPtr hUpdate, IntPtr lpType, IntPtr lpName, ushort wLanguage, byte[] lpData, uint cbData);

  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool EndUpdateResource(IntPtr hUpdate, bool fDiscard);

  const int RT_ICON = 3;
  const int RT_GROUP_ICON = 14;

  [StructLayout(LayoutKind.Sequential, Pack = 1)]
  struct IconDir {
    public ushort Reserved;
    public ushort Type;
    public ushort Count;
  }

  [StructLayout(LayoutKind.Sequential, Pack = 1)]
  struct IconDirEntry {
    public byte Width;
    public byte Height;
    public byte ColorCount;
    public byte Reserved;
    public ushort Planes;
    public ushort BitCount;
    public uint BytesInRes;
    public uint ImageOffset;
  }

  [StructLayout(LayoutKind.Sequential, Pack = 1)]
  struct GrpIconDirEntry {
    public byte Width;
    public byte Height;
    public byte ColorCount;
    public byte Reserved;
    public ushort Planes;
    public ushort BitCount;
    public uint BytesInRes;
    public ushort Id;
  }

  public static void Embed(string exePath, string icoPath) {
    byte[] ico = File.ReadAllBytes(icoPath);
    if (ico.Length < 6) throw new InvalidDataException("ICO too small");

    ushort count = BitConverter.ToUInt16(ico, 4);
    if (count == 0) throw new InvalidDataException("ICO has no images");

    IntPtr update = BeginUpdateResource(exePath, false);
    if (update == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "BeginUpdateResource failed");

    try {
      using (var group = new MemoryStream()) {
        group.Write(BitConverter.GetBytes((ushort)0), 0, 2); // reserved
        group.Write(BitConverter.GetBytes((ushort)1), 0, 2); // type icon
        group.Write(BitConverter.GetBytes(count), 0, 2);

        for (int i = 0; i < count; i++) {
          int entryOffset = 6 + (i * 16);
          byte width = ico[entryOffset];
          byte height = ico[entryOffset + 1];
          byte colorCount = ico[entryOffset + 2];
          ushort planes = BitConverter.ToUInt16(ico, entryOffset + 4);
          ushort bitCount = BitConverter.ToUInt16(ico, entryOffset + 6);
          uint bytesInRes = BitConverter.ToUInt32(ico, entryOffset + 8);
          uint imageOffset = BitConverter.ToUInt32(ico, entryOffset + 12);

          byte[] image = new byte[bytesInRes];
          Buffer.BlockCopy(ico, (int)imageOffset, image, 0, (int)bytesInRes);

          ushort iconId = (ushort)(i + 1);
          if (!UpdateResource(update, (IntPtr)RT_ICON, (IntPtr)iconId, 0x0409, image, (uint)image.Length)) {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "UpdateResource RT_ICON failed");
          }

          group.WriteByte(width);
          group.WriteByte(height);
          group.WriteByte(colorCount);
          group.WriteByte(0);
          group.Write(BitConverter.GetBytes(planes), 0, 2);
          group.Write(BitConverter.GetBytes(bitCount), 0, 2);
          group.Write(BitConverter.GetBytes(bytesInRes), 0, 4);
          group.Write(BitConverter.GetBytes(iconId), 0, 2);
        }

        byte[] groupBytes = group.ToArray();
        // Name 1 = MAINICON
        if (!UpdateResource(update, (IntPtr)RT_GROUP_ICON, (IntPtr)1, 0x0409, groupBytes, (uint)groupBytes.Length)) {
          throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "UpdateResource RT_GROUP_ICON failed");
        }
      }

      if (!EndUpdateResource(update, false)) {
        throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "EndUpdateResource failed");
      }
      update = IntPtr.Zero;
    } finally {
      if (update != IntPtr.Zero) EndUpdateResource(update, true);
    }
  }
}
"@

[PeIconEmbedder]::Embed((Resolve-Path -LiteralPath $Exe).Path, (Resolve-Path -LiteralPath $Ico).Path)
Write-Host "Embedded icon into $Exe"
