package org.rufus.swift;

import android.hardware.usb.*;
import java.io.*;
import java.nio.*;
import java.util.Arrays;

final class UsbDisk implements Closeable {
    private final UsbDeviceConnection connection;
    private final UsbInterface port;
    private final UsbEndpoint input, output;
    private int tag;

    static UsbInterface storagePort(UsbDevice device) {
        for (int i = 0; i < device.getInterfaceCount(); i++) {
            UsbInterface port = device.getInterface(i);
            if (port.getInterfaceClass() == UsbConstants.USB_CLASS_MASS_STORAGE
                && port.getInterfaceSubclass() == 6 && port.getInterfaceProtocol() == 80
                && endpoint(port, UsbConstants.USB_DIR_IN) != null
                && endpoint(port, UsbConstants.USB_DIR_OUT) != null) return port;
        }
        return null;
    }

    private static UsbEndpoint endpoint(UsbInterface port, int direction) {
        for (int i = 0; i < port.getEndpointCount(); i++) {
            UsbEndpoint ep = port.getEndpoint(i);
            if (ep.getType() == UsbConstants.USB_ENDPOINT_XFER_BULK && ep.getDirection() == direction) return ep;
        }
        return null;
    }

    UsbDisk(UsbManager manager, UsbDevice device) throws IOException {
        port = storagePort(device);
        if (port == null) throw new IOException("This drive does not expose a compatible USB storage interface.");
        input = endpoint(port, UsbConstants.USB_DIR_IN);
        output = endpoint(port, UsbConstants.USB_DIR_OUT);
        connection = manager.openDevice(device);
        if (connection == null) throw new IOException("Could not open the USB drive.");
        if (!connection.claimInterface(port, false)) {
            connection.close();
            throw new IOException("The USB drive is in use by the system. Unmount it and try again.");
        }
    }

    private void transfer(UsbEndpoint endpoint, byte[] data, int count) throws IOException {
        if (connection.bulkTransfer(endpoint, data, count, 10000) != count) {
            throw new IOException("The USB drive timed out or returned an incomplete transfer.");
        }
    }

    private void command(byte[] cdb, byte[] data, int length, boolean read) throws IOException {
        int sequence = ++tag;
        ByteBuffer request = ByteBuffer.allocate(31).order(ByteOrder.LITTLE_ENDIAN);
        request.putInt(0x43425355).putInt(sequence).putInt(length)
            .put((byte) (read ? 0x80 : 0)).put((byte) 0).put((byte) cdb.length).put(cdb);
        transfer(output, request.array(), 31);
        if (length > 0) transfer(read ? input : output, data, length);
        byte[] response = new byte[13];
        transfer(input, response, response.length);
        ByteBuffer status = ByteBuffer.wrap(response).order(ByteOrder.LITTLE_ENDIAN);
        if (status.getInt() != 0x53425355 || status.getInt() != sequence
            || status.getInt() != 0 || status.get() != 0) {
            throw new IOException("The USB drive rejected a storage command.");
        }
    }

    long[] getGeometry() throws IOException {
        byte[] capacity = new byte[8];
        command(new byte[] {0x25, 0, 0, 0, 0, 0, 0, 0, 0, 0}, capacity, capacity.length, true);
        ByteBuffer geometry = ByteBuffer.wrap(capacity);
        long lastBlock = Integer.toUnsignedLong(geometry.getInt());
        int block = geometry.getInt();
        if (lastBlock == 0xffffffffL || block < 512 || block > 16384 || (block & (block - 1)) != 0) {
            throw new IOException("Unsupported drive sector geometry.");
        }
        return new long[] {lastBlock + 1, block};
    }

    void writeImage(InputStream source, long size) throws IOException {
        long[] geom = getGeometry();
        long totalBlocks = geom[0];
        int block = (int) geom[1];
        long alignedBlocks = (size + block - 1) / block;
        if (size <= 0 || alignedBlocks > totalBlocks) {
            throw new IOException("The image does not fit the drive or its sector layout is unsupported.");
        }

        byte[] buffer = new byte[16384];
        long lba = 0;
        for (long remaining = size; remaining > 0;) {
            int count = (int) Math.min(remaining, buffer.length);
            int offset = 0;
            while (offset < count) {
                int read = source.read(buffer, offset, count - offset);
                if (read <= 0) throw new EOFException("The image ended early. The USB drive may be incomplete.");
                offset += read;
            }
            int blocks = (count + block - 1) / block;
            int paddedCount = blocks * block;
            if (paddedCount > count) {
                Arrays.fill(buffer, count, paddedCount, (byte) 0);
            }
            byte[] write = ByteBuffer.allocate(10).put((byte) 0x2a).put((byte) 0)
                .putInt((int) lba).put((byte) 0).putShort((short) blocks).array();
            command(write, buffer, paddedCount, false);
            lba += blocks;
            remaining -= count;
        }
        command(new byte[] {0x35, 0, 0, 0, 0, 0, 0, 0, 0, 0}, null, 0, false);
    }

    void backupDrive(OutputStream destination) throws IOException {
        long[] geom = getGeometry();
        long totalBlocks = geom[0];
        int block = (int) geom[1];
        byte[] buffer = new byte[16384];
        int blocksPerChunk = buffer.length / block;

        for (long lba = 0; lba < totalBlocks;) {
            int toReadBlocks = (int) Math.min(blocksPerChunk, totalBlocks - lba);
            int bytesToRead = toReadBlocks * block;
            byte[] readCmd = ByteBuffer.allocate(10).put((byte) 0x28).put((byte) 0)
                .putInt((int) lba).put((byte) 0).putShort((short) toReadBlocks).array();
            command(readCmd, buffer, bytesToRead, true);
            destination.write(buffer, 0, bytesToRead);
            lba += toReadBlocks;
        }
    }

    int checkBadBlocks(int passes) throws IOException {
        long[] geom = getGeometry();
        long totalBlocks = geom[0];
        int block = (int) geom[1];
        byte[] buffer = new byte[16384];
        int blocksPerChunk = buffer.length / block;
        int errors = 0;

        for (int p = 0; p < passes; p++) {
            for (long lba = 0; lba < totalBlocks;) {
                int toReadBlocks = (int) Math.min(blocksPerChunk, totalBlocks - lba);
                int bytesToRead = toReadBlocks * block;
                byte[] readCmd = ByteBuffer.allocate(10).put((byte) 0x28).put((byte) 0)
                    .putInt((int) lba).put((byte) 0).putShort((short) toReadBlocks).array();
                try {
                    command(readCmd, buffer, bytesToRead, true);
                } catch (Exception e) {
                    errors++;
                }
                lba += toReadBlocks;
            }
        }
        return errors;
    }

    void formatFat32(String label, boolean isFreeDos) throws IOException {
        long[] geom = getGeometry();
        long totalBlocks = geom[0];
        int block = (int) geom[1];
        if (totalBlocks < 2048 + 65536) {
            throw new IOException("Drive capacity is too small for FAT32 formatting.");
        }

        // LBA 0: MBR with 1 partition starting at sector 2048
        byte[] mbr = new byte[block];
        mbr[510] = 0x55;
        mbr[511] = (byte) 0xAA;
        ByteBuffer part = ByteBuffer.wrap(mbr, 446, 16).order(ByteOrder.LITTLE_ENDIAN);
        part.put((byte) 0x80); // bootable
        part.put((byte) 0x20).put((byte) 0x21).put((byte) 0x00); // CHS start
        part.put((byte) 0x0C); // FAT32 LBA
        part.put((byte) 0xFE).put((byte) 0xFF).put((byte) 0xFF); // CHS end
        part.putInt(2048); // Start LBA
        long partSectors = totalBlocks - 2048;
        part.putInt((int) Math.min(partSectors, 0xFFFFFFFFL)); // Sector count

        // Write MBR
        byte[] writeMbr = ByteBuffer.allocate(10).put((byte) 0x2A).put((byte) 0)
            .putInt(0).put((byte) 0).putShort((short) 1).array();
        command(writeMbr, mbr, block, false);

        // LBA 2048: FAT32 Volume Boot Record
        byte[] vbr = new byte[block];
        ByteBuffer boot = ByteBuffer.wrap(vbr).order(ByteOrder.LITTLE_ENDIAN);
        boot.put((byte) 0xEB).put((byte) 0x58).put((byte) 0x90); // Jump
        byte[] oem = "RUFUS   ".getBytes();
        boot.put(oem, 0, 8);
        boot.putShort((short) block); // bytes per sector
        boot.put((byte) 8); // sectors per cluster (4KB)
        boot.putShort((short) 32); // reserved sectors
        boot.put((byte) 2); // number of FATs
        boot.putShort((short) 0);
        boot.putShort((short) 0);
        boot.put((byte) 0xF8); // Media descriptor
        boot.putShort((short) 0);
        boot.putShort((short) 63); // sectors per track
        boot.putShort((short) 255); // heads
        boot.putInt(2048); // hidden sectors
        boot.putInt((int) partSectors); // total sectors 32
        int fatSize = (int) ((partSectors / 8 * 4 + block - 1) / block);
        boot.putInt(fatSize); // sectors per FAT
        boot.putShort((short) 0); // flags
        boot.putShort((short) 0); // version
        boot.putInt(2); // root directory cluster
        boot.putShort((short) 1); // FSInfo sector
        boot.putShort((short) 6); // backup boot sector
        boot.position(66);
        boot.put((byte) 0x29); // boot sig
        boot.putInt(0x12345678); // volume ID
        byte[] volLabel = String.format("%-11s", (label.isEmpty() ? "RUFUS" : label).toUpperCase()).substring(0, 11).getBytes();
        boot.put(volLabel);
        boot.put("FAT32   ".getBytes());
        vbr[510] = 0x55;
        vbr[511] = (byte) 0xAA;

        byte[] writeVbr = ByteBuffer.allocate(10).put((byte) 0x2A).put((byte) 0)
            .putInt(2048).put((byte) 0).putShort((short) 1).array();
        command(writeVbr, vbr, block, false);

        // LBA 2049: FSInfo
        byte[] fsInfo = new byte[block];
        ByteBuffer info = ByteBuffer.wrap(fsInfo).order(ByteOrder.LITTLE_ENDIAN);
        info.putInt(0x41615252);
        info.position(484);
        info.putInt(0x61417272);
        info.putInt((int) ((partSectors - 32 - (2 * fatSize)) / 8)); // free clusters
        info.putInt(3); // next free cluster
        fsInfo[510] = 0x55;
        fsInfo[511] = (byte) 0xAA;
        byte[] writeInfo = ByteBuffer.allocate(10).put((byte) 0x2A).put((byte) 0)
            .putInt(2049).put((byte) 0).putShort((short) 1).array();
        command(writeInfo, fsInfo, block, false);

        // Initialize First Sector of FAT table (LBA 2048 + 32)
        byte[] fatSector = new byte[block];
        ByteBuffer fat = ByteBuffer.wrap(fatSector).order(ByteOrder.LITTLE_ENDIAN);
        fat.putInt(0x0FFFFFF8); // Cluster 0: Media
        fat.putInt(0x0FFFFFFF); // Cluster 1: EOF
        fat.putInt(0x0FFFFFFF); // Cluster 2: Root dir EOF
        byte[] writeFat = ByteBuffer.allocate(10).put((byte) 0x2A).put((byte) 0)
            .putInt(2080).put((byte) 0).putShort((short) 1).array();
        command(writeFat, fatSector, block, false);

        command(new byte[] {0x35, 0, 0, 0, 0, 0, 0, 0, 0, 0}, null, 0, false);
    }

    @Override public void close() {
        connection.releaseInterface(port);
        connection.close();
    }
}
