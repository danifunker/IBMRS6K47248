5911c addi    r1,r1,-4
59120 mflr    r0
59124 stw     r0,0(r1)
59128 addi    r1,r1,-24
5912c bl      0x59144  <init_main>   ; call init_main(r3=?, r4=?, r5=?, r6=?)
59130 addi    r1,r1,24
59134 lwz     r0,0(r1)
59138 mtlr    r0
5913c addi    r1,r1,4
59140 blr
00059144 <init_main>:
59144 mflr    r0
59148 stmw    r29,-12(r1)
5914c stw     r0,8(r1)
59150 stwu    r1,-80(r1)
59154 stw     r4,60(r1)
59158 lwz     r4,0(r2)   ; TOC+0 -> D_5f008
5915c stw     r3,56(r1)
59160 lwz     r11,0(r4)
59164 li      r3,-1
59168 li      r4,-1
5916c bl      0x59490   ; SVC None(r3=0xffffffff, r4=0xffffffff, r5=?)
59170 lwz     r2,20(r1)
59174 lwz     r4,0(r3)
59178 lwz     r9,4(r2)   ; TOC+4 -> D_60480
5917c cmpwi   r4,0
59180 li      r31,8
59184 li      r30,0
59188 addic   r8,r3,-4
5918c lwz     r10,8(r2)   ; TOC+8 -> D_5ef44
59190 ble     0x59224
59194 lwz     r0,12(r2)   ; TOC+12 -> D_59144
59198 lwz     r12,16(r2)   ; TOC+16 -> D_60484
5919c lwz     r11,20(r2)   ; TOC+20 -> D_60488
591a0 lwz     r5,24(r2)   ; TOC+24 -> D_6048c
591a4 lwz     r4,28(r2)   ; TOC+28 -> D_60490
591a8 lwz     r29,32(r2)   ; TOC+32 -> D_60494
591ac addi    r6,r9,0
591b0 lwzu    r7,8(r8)
591b4 addic   r30,r30,1
591b8 cmplwi  cr1,r7,5
591bc slwi    r7,r7,2
591c0 bgt     cr1,0x59258
591c4 lwzx    r7,r10,r7
591c8 addc    r7,r7,r0
591cc mtctr   r7
591d0 bctr
591d4 lwz     r7,4(r8)
591d8 stw     r7,0(r6)
591dc b       0x59218
591e0 lwz     r7,4(r8)
591e4 stw     r7,0(r29)
591e8 b       0x59218
591ec lwz     r7,4(r8)
591f0 stw     r7,0(r4)
591f4 b       0x59218
591f8 lwz     r7,4(r8)
591fc stw     r7,0(r5)
59200 b       0x59218
59204 lwz     r7,4(r8)
59208 stw     r7,0(r11)
5920c b       0x59218
59210 lwz     r7,4(r8)
59214 stw     r7,0(r12)
59218 lwz     r7,0(r3)
5921c cmpw    r30,r7
59220 blt     0x591b0
59224 lwz     r4,0(r9)
59228 li      r3,0
5922c lwzu    r11,12(r4)
59230 bl      0x59490   ; SVC manager_level_verify(r3=0x0, r4=?, r5=?)
59234 lwz     r2,20(r1)
59238 cmpwi   r3,0
5923c lwz     r3,56(r1)
59240 lwz     r4,60(r1)
59244 beq     0x59254
59248 bl      0x594b0  <main>   ; call main(r3=?, r4=?, r5=?, r6=?)
5924c crmove  4*cr7+so,4*cr7+so
59250 addi    r31,r3,0
59254 addi    r3,r31,0
59258 lwz     r12,88(r1)
5925c addic   r1,r1,80
59260 mtlr    r12
59264 lmw     r29,-12(r1)
59268 blr
5926c .long 0x0
59270 .long 0x2041
59274 lwz     r0,512(r3)
59278 .long 0x0
5927c .long 0x128
59280 .long 0x9696e
59284 xori    r20,r11,24429
59288 ori     r9,r11,28160
5928c mtdec   r3
59290 blr
59294 mfdec   r3
59298 blr
5929c mfpvr   r3
592a0 srwi    r3,r3,16
592a4 cmpwi   r3,1
592a8 bne     0x592b4
592ac mfrtcu  r3
592b0 blr
592b4 mftbu   r3
592b8 blr
592bc mfpvr   r3
592c0 srwi    r3,r3,16
592c4 cmpwi   r3,1
592c8 bne     0x592d4
592cc mfrtcl  r3
592d0 blr
592d4 mftb    r3
592d8 blr
592dc mfpvr   r0
592e0 srwi    r0,r0,16
592e4 cmpwi   r0,1
592e8 bne     0x592f4
592ec mtrtcu  r3
592f0 blr
592f4 mttbu   r3
592f8 blr
592fc mfpvr   r0
59300 srwi    r0,r0,16
59304 cmpwi   r0,1
59308 bne     0x59314
5930c mtrtcl  r3
59310 blr
59314 mttbl   r3
59318 blr
5931c mfmsr   r3
59320 blr
59324 isync
59328 hwsync
5932c mtmsr   r3
59330 isync
59334 hwsync
59338 blr
5933c mfmsr   r3
59340 rlwinm  r3,r3,17,31,31
59344 blr
59348 mfmsr   r3
5934c ori     r3,r3,32768
59350 isync
59354 mtmsr   r3
59358 isync
5935c blr
59360 mfmsr   r3
59364 rlwinm  r3,r3,0,17,15
59368 isync
5936c mtmsr   r3
59370 isync
59374 blr
59378 mfsrr0  r3
5937c blr
59380 mfsrr1  r3
59384 blr
59388 mfdar   r3
5938c blr
59390 mfdsisr r3
59394 blr
59398 mfpir   r3
5939c blr
593a0 mfpvr   r3
593a4 blr
593a8 isync
593ac slwi    r3,r3,28
593b0 mtsrin  r4,r3
593b4 isync
593b8 isync
593bc blr
593c0 slwi    r3,r3,28
593c4 mfsrin  r3,r3
593c8 blr
593cc b       0x593cc
593d0 addi    r1,r1,-12
593d4 mflr    r0
593d8 mfctr   r12
593dc stw     r0,0(r1)
593e0 stw     r12,4(r1)
593e4 mtctr   r3
593e8 bctrl
593ec lwz     r0,0(r1)
593f0 lwz     r12,4(r1)
593f4 addi    r1,r1,12
593f8 mtlr    r0
593fc mtctr   r12
59400 blr
59404 addi    r1,r1,-12
59408 mflr    r0
5940c mfctr   r12
59410 stw     r0,0(r1)
59414 stw     r12,4(r1)
59418 mtctr   r5
5941c addi    r20,r6,0
59420 xor     r5,r5,r5
59424 addi    r6,r5,0
59428 addi    r7,r5,0
5942c addi    r8,r5,0
59430 addi    r9,r5,0
59434 addi    r10,r5,0
59438 bctrl
5943c lwz     r0,0(r1)
59440 lwz     r12,4(r1)
59444 addi    r1,r1,12
59448 mtlr    r0
5944c mtctr   r12
59450 blr
59454 addi    r1,r1,-12
59458 mflr    r0
5945c mfctr   r12
59460 stw     r0,0(r1)
59464 stw     r12,4(r1)
59468 mtctr   r3
5946c ori     r3,r4,0
59470 ori     r4,r5,0
59474 bctrl
59478 lwz     r0,0(r1)
5947c lwz     r12,4(r1)
59480 addi    r1,r1,12
59484 mtlr    r0
59488 mtctr   r12
5948c blr
59490 lwz     r0,0(r11)
59494 stw     r2,20(r1)
59498 mtctr   r0
5949c lwz     r2,4(r11)
594a0 lwz     r11,8(r11)
594a4 bctr
594a8 eieio
594ac blr
000594b0 <main>:
594b0 stmw    r27,-20(r1)
594b4 mflr    r0
594b8 lwz     r30,4(r2)   ; TOC+4 -> D_60480
594bc stw     r0,8(r1)
594c0 lwz     r7,0(r30)
594c4 lis     r31,21299
594c8 stwu    r1,-96(r1)
594cc addic   r3,r31,167
594d0 lwzu    r11,512(r7)
594d4 bl      0x59490   ; SVC checkpoint(r3=0x533300a7, r4=?, r5=?)
594d8 lwz     r2,20(r1)
594dc li      r3,0
594e0 bl      0x595bc  <s3_query>   ; call s3_query(r3=0x0, r4=?, r5=?, r6=?)
594e4 addi    r27,r3,0
594e8 li      r29,0
594ec lwz     r28,32(r2)   ; TOC+32 -> D_60494
594f0 lwz     r7,0(r28)
594f4 addi    r4,r29,0
594f8 lwzu    r11,4(r7)
594fc addic   r29,r29,1
59500 li      r3,1
59504 li      r5,0
59508 bl      0x59490   ; SVC manager_query(r3=0x1, r4=0x0, r5=0x0)
5950c lwz     r2,20(r1)
59510 cmplw   r3,r27
59514 cmpwi   cr1,r3,0
59518 beq     0x59544
5951c bne     cr1,0x594f0
59520 li      r3,1
59524 bl      0x59fac  <s3_Found>   ; call s3_Found(r3=0x1, r4=?, r5=?, r6=?)
59528 crmove  4*cr7+so,4*cr7+so
5952c cmpwi   r3,0
59530 li      r29,8
59534 li      r3,513
59538 li      r4,3
5953c bne     0x5954c
59540 b       0x59574
59544 li      r3,8
59548 b       0x5958c
5954c bl      0x5b944  <s3_init>   ; call s3_init(r3=0x8, r4=0x3, r5=?, r6=?)
59550 crmove  4*cr7+so,4*cr7+so
59554 lwz     r7,0(r28)
59558 lwz     r4,64(r2)   ; TOC+64 -> D_60224
5955c lwzu    r11,12(r7)
59560 li      r3,1
59564 li      r5,0
59568 bl      0x59490   ; SVC manager_level_verify(r3=0x1, r4=?, r5=0x0)
5956c lwz     r2,20(r1)
59570 addi    r29,r3,0
59574 lwz     r7,0(r30)
59578 addic   r3,r31,168
5957c lwzu    r11,512(r7)
59580 bl      0x59490   ; SVC checkpoint(r3=0x533300a8, r4=?, r5=?)
59584 lwz     r2,20(r1)
59588 addi    r3,r29,0
5958c lwz     r12,104(r1)
59590 addic   r1,r1,96
59594 mtlr    r12
59598 lmw     r27,-20(r1)
5959c blr
595a0 .long 0x0
595a4 .long 0x2041
595a8 lwz     r0,512(r5)
595ac .long 0x0
595b0 .long 0xf0
595b4 .long 0x46d61
595b8 xori    r14,r11,0
000595bc <s3_query>:
595bc lwz     r4,68(r2)   ; TOC+68 -> D_60268
595c0 slwi    r3,r3,2
595c4 lwzx    r3,r4,r3
595c8 blr
595cc .long 0x0
595d0 .long 0x2040
595d4 .long 0x100
595d8 .long 0x0
595dc .long 0x10
595e0 .long 0x87333
595e4 rlwnm.  r17,r27,r14,21,18
595e8 andi.   r25,r19,0
000595ec <s3_query_device>:
595ec lwz     r4,40(r2)   ; TOC+40 -> D_5f010
595f0 lbz     r4,0(r4)
595f4 slwi    r5,r3,2
595f8 cmpwi   r4,0
595fc cmpwi   cr6,r4,2
59600 cmpwi   cr1,r4,1
59604 lwz     r4,72(r2)   ; TOC+72 -> D_60320
59608 beq     0x59624
5960c lwz     r4,76(r2)   ; TOC+76 -> D_60324
59610 beq     cr1,0x59634
59614 addi    r4,r5,0
59618 lwz     r3,80(r2)   ; TOC+80 -> D_60328
5961c beq     cr6,0x5962c
59620 b       0x59638
59624 lwzx    r0,r4,r5
59628 b       0x59638
5962c lwzx    r0,r3,r4
59630 b       0x59638
59634 lwzx    r0,r4,r5
59638 addic   r3,r0,0
5963c blr
59640 .long 0x0
59644 .long 0x2040
59648 .long 0x100
5964c .long 0x0
59650 .long 0x54
59654 .long 0xf7333
59658 rlwnm.  r17,r27,r14,21,18
5965c andi.   r25,r19,24420
59660 oris    r22,r11,26979
59664 oris    r0,r8,0
00059668 <s3_diags_hook>:
59668 cmpwi   cr1,r3,16
5966c addic   r3,r3,-90
59670 cmplwi  r3,8
59674 lwz     r0,84(r2)   ; TOC+84 -> D_5ef5c
59678 slwi    r3,r3,2
5967c addc    r3,r0,r3
59680 lwz     r0,88(r2)   ; TOC+88 -> D_594b0
59684 bgt     0x59698
59688 lwz     r3,136(r3)
5968c addc    r3,r0,r3
59690 mtctr   r3
59694 bctr
59698 beq     cr1,0x596e4
5969c b       0x596f0
596a0 lwz     r3,64(r2)   ; TOC+64 -> D_60224
596a4 blr
596a8 lwz     r3,40(r2)   ; TOC+40 -> D_5f010
596ac lbz     r3,0(r3)
596b0 blr
596b4 lwz     r3,48(r2)   ; TOC+48 -> D_5ff1c
596b8 lbz     r3,0(r3)
596bc blr
596c0 lwz     r3,36(r2)   ; TOC+36 -> D_5f00c
596c4 lbz     r3,0(r3)
596c8 blr
596cc lwz     r3,92(r2)   ; TOC+92 -> D_603ec
596d0 blr
596d4 lwz     r3,96(r2)   ; TOC+96 -> D_603f8
596d8 blr
596dc lwz     r3,100(r2)   ; TOC+100 -> D_60404
596e0 blr
596e4 lwz     r3,64(r2)   ; TOC+64 -> D_60224
596e8 lwz     r3,64(r3)
596ec blr
596f0 li      r3,0
596f4 blr
596f8 .long 0x0
596fc .long 0x2040
59700 .long 0x100
59704 .long 0x0
59708 .long 0x90
5970c .long 0xd7333
59710 rlwnm.  r4,r27,r13,5,16
59714 oris    r19,r27,24424
59718 xoris   r15,r27,27392
0005971c <build_s3>:
5971c stmw    r23,-36(r1)
59720 mflr    r0
59724 lwz     r26,4(r2)   ; TOC+4 -> D_60480
59728 stw     r0,8(r1)
5972c lwz     r3,0(r26)
59730 stwu    r1,-128(r1)
59734 li      r23,16773
59738 lwzu    r11,672(r3)
5973c bl      0x59490   ; SVC pci_config_query_slots(r3=?, r4=?, r5=?)
59740 lwz     r2,20(r1)
59744 li      r0,-1
59748 addic   r27,r3,-1
5974c stw     r0,56(r1)
59750 lis     r10,-30544
59754 lis     r9,-30528
59758 lis     r3,-30592
5975c lis     r0,-30704
59760 addic   r28,r10,21299
59764 addic   r31,r9,21299
59768 addic   r29,r3,21299
5976c addic   r30,r0,21299
59770 li      r25,0
59774 lwz     r9,0(r26)
59778 addi    r3,r27,0
5977c lwzu    r11,684(r9)
59780 li      r4,0
59784 bl      0x59490   ; SVC pci_config_read_32(r3=?, r4=0x0, r5=?)
59788 lwz     r2,20(r1)
5978c rlwinm  r0,r3,0,16,11
59790 cmplw   r0,r28
59794 beq     0x598c0
59798 cmplw   cr1,r0,r31
5979c beq     cr1,0x598c0
597a0 cmplw   r0,r29
597a4 beq     0x598c0
597a8 cmplw   cr1,r0,r30
597ac addic   r0,r27,-1
597b0 beq     cr1,0x598c0
597b4 addic   r27,r0,0
597b8 b       0x59774
597bc lwz     r0,56(r1)
597c0 cmpwi   r0,-1
597c4 beq     0x59e00
597c8 lwz     r3,32(r2)   ; TOC+32 -> D_60494
597cc lwz     r31,104(r2)   ; TOC+104 -> D_60b9c
597d0 lwz     r9,0(r3)
597d4 addi    r3,r31,0
597d8 lwzu    r11,88(r9)
597dc lwz     r4,108(r2)   ; TOC+108 -> D_60ba0
597e0 bl      0x59490   ; SVC fread(r3=?, r4=?, r5=?)
597e4 lwz     r2,20(r1)
597e8 lwz     r10,0(r31)
597ec lwz     r3,8(r10)
597f0 lwz     r0,0(r10)
597f4 addic   r9,r3,-513
597f8 cmplwi  r9,33
597fc lwz     r10,4(r10)
59800 cmpwi   cr6,r3,279
59804 cmpwi   cr1,r3,259
59808 clrlwi  r30,r10,16
5980c clrlwi  r29,r0,16
59810 bgt     0x59840
59814 lwz     r3,84(r2)   ; TOC+84 -> D_5ef5c
59818 slwi    r9,r9,2
5981c lwzx    r3,r3,r9
59820 lwz     r9,88(r2)   ; TOC+88 -> D_594b0
59824 addc    r3,r3,r9
59828 mtctr   r3
5982c bctr
59830 li      r27,3
59834 b       0x5986c
59838 li      r27,4
5983c b       0x5986c
59840 cmpwi   r3,628
59844 beq     cr6,0x598b0
59848 bgt     cr6,0x5985c
5984c cmpwi   cr6,r3,263
59850 beq     cr1,0x598b8
59854 beq     cr6,0x598b8
59858 b       0x59868
5985c cmpwi   cr1,r3,629
59860 beq     0x598b8
59864 beq     cr1,0x598b0
59868 li      r27,0
5986c cmpwi   cr7,r27,1
59870 cmpwi   cr1,r27,2
59874 cmpwi   r27,3
59878 cmpwi   cr6,r27,4
5987c beq     cr7,0x598a8
59880 beq     cr1,0x598a0
59884 beq     0x59894
59888 beq     cr6,0x59908
5988c li      r28,0
59890 b       0x5990c
59894 mulli   r0,r29,3
59898 clrlwi  r28,r0,16
5989c b       0x5990c
598a0 rlwinm  r28,r0,1,16,30
598a4 b       0x5990c
598a8 addi    r28,r29,0
598ac b       0x5990c
598b0 li      r27,2
598b4 b       0x5986c
598b8 li      r27,1
598bc b       0x5986c
598c0 lwz     r3,0(r26)
598c4 addic   r4,r1,56
598c8 lwzu    r11,700(r3)
598cc addic   r5,r1,60
598d0 addi    r3,r27,0
598d4 bl      0x59490   ; SVC pci_config_slot_2_dev(r3=0x1, r4=?, r5=?)
598d8 lwz     r2,20(r1)
598dc lwz     r9,0(r26)
598e0 addi    r3,r27,0
598e4 lwzu    r11,888(r9)
598e8 bl      0x59490   ; SVC pci_logical_2_physical_slot(r3=0x1, r4=?, r5=?)
598ec lwz     r2,20(r1)
598f0 cmpwi   cr1,r3,0
598f4 addi    r24,r3,0
598f8 bne     cr1,0x597bc
598fc li      r24,0
59900 li      r23,25029
59904 b       0x597bc
59908 rlwinm  r28,r0,2,16,29
5990c lwz     r3,0(r26)
59910 lwz     r0,64(r2)   ; TOC+64 -> D_60224
59914 addi    r9,r3,0
59918 lwzu    r11,748(r3)
5991c lwzu    r31,892(r9)
59920 addic   r3,r0,56
59924 bl      0x59490   ; SVC compress_id(r3=?, r4=?, r5=?)
59928 lwz     r2,20(r1)
5992c addi    r4,r3,0
59930 addi    r11,r31,0
59934 addi    r5,r24,0
59938 addi    r6,r23,0
5993c li      r3,4
59940 li      r7,3
59944 li      r8,1
59948 li      r9,0
5994c li      r10,0
59950 bl      0x59490   ; SVC SetResidualDeviceID(r3=0x4, r4=?, r5=0x0)
59954 lwz     r2,20(r1)
59958 lwz     r9,56(r1)
5995c lwz     r0,60(r1)
59960 lwz     r3,0(r26)
59964 stb     r9,64(r1)
59968 stb     r0,65(r1)
5996c sth     r25,66(r1)
59970 lwzu    r11,896(r3)
59974 li      r3,4
59978 lwz     r4,64(r1)
5997c bl      0x59490   ; SVC SetResidualBusAccess(r3=0x4, r4=?, r5=?)
59980 lwz     r2,20(r1)
59984 lwz     r3,0(r26)
59988 lwzu    r11,900(r3)
5998c bl      0x59490   ; SVC SetResidualAllocated(r3=?, r4=?, r5=?)
59990 lwz     r2,20(r1)
59994 lwz     r3,0(r26)
59998 lis     r4,0
5999c ori     r4,r4,32768
599a0 lwzu    r11,924(r3)
599a4 li      r3,8
599a8 bl      0x59490   ; SVC CreateIRQInfoPacket(r3=0x8, r4=0x8000, r5=?)
599ac lwz     r2,20(r1)
599b0 lwz     r9,0(r26)
599b4 li      r3,1
599b8 lwzu    r11,984(r9)
599bc li      r4,32
599c0 li      r5,258
599c4 li      r6,1
599c8 bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x102)
599cc lwz     r2,20(r1)
599d0 lwz     r9,0(r26)
599d4 li      r3,1
599d8 lwzu    r11,984(r9)
599dc li      r4,32
599e0 li      r5,948
599e4 li      r6,2
599e8 bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x3b4)
599ec lwz     r2,20(r1)
599f0 lwz     r9,0(r26)
599f4 li      r3,1
599f8 lwzu    r11,984(r9)
599fc li      r4,32
59a00 li      r5,952
59a04 li      r6,4
59a08 bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x3b8)
59a0c lwz     r2,20(r1)
59a10 lwz     r9,0(r26)
59a14 li      r3,1
59a18 lwzu    r11,984(r9)
59a1c li      r4,32
59a20 li      r5,959
59a24 li      r6,12
59a28 bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x3bf)
59a2c lwz     r2,20(r1)
59a30 lwz     r9,0(r26)
59a34 li      r3,1
59a38 lwzu    r11,984(r9)
59a3c li      r4,32
59a40 li      r5,972
59a44 li      r6,1
59a48 bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x3cc)
59a4c lwz     r2,20(r1)
59a50 lwz     r9,0(r26)
59a54 li      r3,1
59a58 lwzu    r11,984(r9)
59a5c li      r4,32
59a60 li      r5,974
59a64 li      r6,2
59a68 bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x3ce)
59a6c lwz     r2,20(r1)
59a70 lwz     r9,0(r26)
59a74 li      r3,1
59a78 lwzu    r11,984(r9)
59a7c li      r4,32
59a80 li      r5,980
59a84 li      r6,2
59a88 bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x3d4)
59a8c lwz     r2,20(r1)
59a90 lwz     r9,0(r26)
59a94 li      r3,1
59a98 lwzu    r11,984(r9)
59a9c li      r4,32
59aa0 li      r5,984
59aa4 li      r6,5
59aa8 bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x3d8)
59aac lwz     r2,20(r1)
59ab0 lwz     r9,0(r26)
59ab4 li      r3,1
59ab8 lwzu    r11,984(r9)
59abc li      r4,32
59ac0 li      r5,17128
59ac4 li      r6,1
59ac8 bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x42e8)
59acc lwz     r2,20(r1)
59ad0 lwz     r9,0(r26)
59ad4 li      r3,1
59ad8 lwzu    r11,984(r9)
59adc li      r4,32
59ae0 li      r5,18152
59ae4 li      r6,1
59ae8 bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x46e8)
59aec lwz     r2,20(r1)
59af0 lwz     r9,0(r26)
59af4 li      r3,1
59af8 lwzu    r11,984(r9)
59afc li      r4,32
59b00 li      r5,19176
59b04 li      r6,1
59b08 bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x4ae8)
59b0c lwz     r2,20(r1)
59b10 lwz     r3,0(r26)
59b14 lis     r31,1
59b18 lwzu    r11,984(r3)
59b1c li      r3,1
59b20 li      r4,32
59b24 addic   r5,r31,-32024
59b28 li      r6,1
59b2c bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x82e8)
59b30 lwz     r2,20(r1)
59b34 lwz     r9,0(r26)
59b38 li      r3,1
59b3c lwzu    r11,984(r9)
59b40 li      r4,32
59b44 addic   r5,r31,-31000
59b48 li      r6,1
59b4c bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x86e8)
59b50 lwz     r2,20(r1)
59b54 lwz     r9,0(r26)
59b58 li      r3,1
59b5c lwzu    r11,984(r9)
59b60 li      r4,32
59b64 addic   r5,r31,-29976
59b68 li      r6,1
59b6c bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x8ae8)
59b70 lwz     r2,20(r1)
59b74 lwz     r9,0(r26)
59b78 li      r3,1
59b7c lwzu    r11,984(r9)
59b80 li      r4,32
59b84 addic   r5,r31,-28952
59b88 li      r6,1
59b8c bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x8ee8)
59b90 lwz     r2,20(r1)
59b94 lwz     r9,0(r26)
59b98 li      r3,1
59b9c lwzu    r11,984(r9)
59ba0 li      r4,32
59ba4 addic   r5,r31,-27928
59ba8 li      r6,1
59bac bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x92e8)
59bb0 lwz     r2,20(r1)
59bb4 lwz     r9,0(r26)
59bb8 li      r3,1
59bbc lwzu    r11,984(r9)
59bc0 li      r4,32
59bc4 addic   r5,r31,-26904
59bc8 li      r6,1
59bcc bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x96e8)
59bd0 lwz     r2,20(r1)
59bd4 lwz     r9,0(r26)
59bd8 li      r3,1
59bdc lwzu    r11,984(r9)
59be0 li      r4,32
59be4 addic   r5,r31,-25880
59be8 li      r6,1
59bec bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x9ae8)
59bf0 lwz     r2,20(r1)
59bf4 lwz     r9,0(r26)
59bf8 li      r3,1
59bfc lwzu    r11,984(r9)
59c00 li      r4,32
59c04 addic   r5,r31,-24856
59c08 li      r6,1
59c0c bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0x9ee8)
59c10 lwz     r2,20(r1)
59c14 lwz     r9,0(r26)
59c18 li      r3,1
59c1c lwzu    r11,984(r9)
59c20 li      r4,32
59c24 addic   r5,r31,-23832
59c28 li      r6,1
59c2c bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0xa2e8)
59c30 lwz     r2,20(r1)
59c34 lwz     r9,0(r26)
59c38 li      r3,1
59c3c lwzu    r11,984(r9)
59c40 li      r4,32
59c44 addic   r5,r31,-22808
59c48 li      r6,1
59c4c bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0xa6e8)
59c50 lwz     r2,20(r1)
59c54 lwz     r9,0(r26)
59c58 li      r3,1
59c5c lwzu    r11,984(r9)
59c60 li      r4,32
59c64 addic   r5,r31,-21784
59c68 li      r6,1
59c6c bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0xaae8)
59c70 lwz     r2,20(r1)
59c74 lwz     r9,0(r26)
59c78 li      r3,1
59c7c lwzu    r11,984(r9)
59c80 li      r4,32
59c84 addic   r5,r31,-20760
59c88 li      r6,1
59c8c bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0xaee8)
59c90 lwz     r2,20(r1)
59c94 lwz     r9,0(r26)
59c98 li      r3,1
59c9c lwzu    r11,984(r9)
59ca0 li      r4,32
59ca4 addic   r5,r31,-19736
59ca8 li      r6,1
59cac bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0xb2e8)
59cb0 lwz     r2,20(r1)
59cb4 lwz     r9,0(r26)
59cb8 li      r3,1
59cbc lwzu    r11,984(r9)
59cc0 li      r4,32
59cc4 addic   r5,r31,-18712
59cc8 li      r6,1
59ccc bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0xb6e8)
59cd0 lwz     r2,20(r1)
59cd4 lwz     r9,0(r26)
59cd8 li      r3,1
59cdc lwzu    r11,984(r9)
59ce0 li      r4,32
59ce4 addic   r5,r31,-17688
59ce8 li      r6,1
59cec bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0xbae8)
59cf0 lwz     r2,20(r1)
59cf4 lwz     r9,0(r26)
59cf8 li      r3,1
59cfc lwzu    r11,984(r9)
59d00 li      r4,32
59d04 addic   r5,r31,-16664
59d08 li      r6,1
59d0c bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0xbee8)
59d10 lwz     r2,20(r1)
59d14 lwz     r9,0(r26)
59d18 li      r3,1
59d1c lwzu    r11,984(r9)
59d20 li      r4,32
59d24 addic   r5,r31,-7448
59d28 li      r6,1
59d2c bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0xe2e8)
59d30 lwz     r2,20(r1)
59d34 lwz     r3,0(r26)
59d38 addic   r5,r31,-7446
59d3c lwzu    r11,984(r3)
59d40 li      r3,1
59d44 li      r4,32
59d48 li      r6,1
59d4c bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x1, r4=0x20, r5=0xe2ea)
59d50 lwz     r2,20(r1)
59d54 lwz     r3,0(r26)
59d58 li      r4,32
59d5c lwzu    r11,984(r3)
59d60 li      r3,2
59d64 lis     r5,640
59d68 lis     r6,32
59d6c bl      0x59490   ; SVC CreateVendorIOPacket(r3=0x2, r4=0x20, r5=0x2800000)
59d70 lwz     r2,20(r1)
59d74 lwz     r9,0(r26)
59d78 addi    r3,r27,0
59d7c lwzu    r11,972(r9)
59d80 addi    r5,r29,0
59d84 addi    r6,r30,0
59d88 addi    r7,r28,0
59d8c li      r4,0
59d90 lis     r8,-15744
59d94 lis     r9,32
59d98 bl      0x59490   ; SVC CreateDispPacket(r3=0x1, r4=0x0, r5=?)
59d9c lwz     r2,20(r1)
59da0 lwz     r3,0(r26)
59da4 lwzu    r11,948(r3)
59da8 bl      0x59490   ; SVC CreateEndPacket(r3=?, r4=?, r5=?)
59dac lwz     r2,20(r1)
59db0 lwz     r3,0(r26)
59db4 lwzu    r11,904(r3)
59db8 bl      0x59490   ; SVC SetResidualPossible(r3=?, r4=?, r5=?)
59dbc lwz     r2,20(r1)
59dc0 lwz     r3,0(r26)
59dc4 lwzu    r11,948(r3)
59dc8 bl      0x59490   ; SVC CreateEndPacket(r3=?, r4=?, r5=?)
59dcc lwz     r2,20(r1)
59dd0 lwz     r3,0(r26)
59dd4 lwzu    r11,908(r3)
59dd8 bl      0x59490   ; SVC SetResidualCompatible(r3=?, r4=?, r5=?)
59ddc lwz     r2,20(r1)
59de0 lwz     r3,0(r26)
59de4 lwzu    r11,948(r3)
59de8 bl      0x59490   ; SVC CreateEndPacket(r3=?, r4=?, r5=?)
59dec lwz     r2,20(r1)
59df0 lwz     r3,0(r26)
59df4 lwzu    r11,912(r3)
59df8 bl      0x59490   ; SVC UpdateResidualDeviceHandle(r3=?, r4=?, r5=?)
59dfc lwz     r2,20(r1)
59e00 lwz     r12,136(r1)
59e04 addic   r1,r1,128
59e08 mtlr    r12
59e0c lmw     r23,-36(r1)
59e10 blr
59e14 .long 0x0
59e18 .long 0x2041
59e1c lwz     r0,256(r9)
59e20 .long 0x0
59e24 .long 0x6f8
59e28 .long 0x86275
59e2c xori    r12,r11,25695
59e30 andi.   r19,r25,0
59e34 .long 0x0
00059e38 <S3_Unlock>:
59e38 stw     r31,-4(r1)
59e3c mflr    r0
59e40 lwz     r31,4(r2)   ; TOC+4 -> D_60480
59e44 stw     r0,8(r1)
59e48 lwz     r5,0(r31)
59e4c stwu    r1,-80(r1)
59e50 li      r3,980
59e54 li      r4,56
59e58 lwzu    r11,344(r5)
59e5c bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x38, r5=?)
59e60 lwz     r2,20(r1)
59e64 lwz     r4,0(r31)
59e68 li      r3,981
59e6c lwzu    r11,344(r4)
59e70 li      r4,72
59e74 bl      0x59490   ; SVC out8(r3=0x3d5, r4=0x48, r5=?)
59e78 lwz     r2,20(r1)
59e7c lwz     r4,0(r31)
59e80 li      r3,980
59e84 lwzu    r11,344(r4)
59e88 li      r4,57
59e8c bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x39, r5=?)
59e90 lwz     r2,20(r1)
59e94 lwz     r4,0(r31)
59e98 li      r3,981
59e9c lwzu    r11,344(r4)
59ea0 li      r4,165
59ea4 bl      0x59490   ; SVC out8(r3=0x3d5, r4=0xa5, r5=?)
59ea8 lwz     r2,20(r1)
59eac lwz     r4,0(r31)
59eb0 li      r3,980
59eb4 lwzu    r11,344(r4)
59eb8 li      r4,17
59ebc bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x11, r5=?)
59ec0 lwz     r2,20(r1)
59ec4 lwz     r4,0(r31)
59ec8 li      r3,981
59ecc lwzu    r11,324(r4)
59ed0 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
59ed4 lwz     r2,20(r1)
59ed8 lwz     r5,0(r31)
59edc clrlwi  r4,r3,25
59ee0 lwzu    r11,344(r5)
59ee4 li      r3,981
59ee8 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
59eec lwz     r2,20(r1)
59ef0 lwz     r4,0(r31)
59ef4 li      r3,980
59ef8 lwzu    r11,344(r4)
59efc li      r4,64
59f00 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x40, r5=?)
59f04 lwz     r2,20(r1)
59f08 lwz     r4,0(r31)
59f0c li      r3,981
59f10 lwzu    r11,324(r4)
59f14 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
59f18 lwz     r2,20(r1)
59f1c lwz     r5,0(r31)
59f20 clrlwi  r3,r3,24
59f24 ori     r4,r3,1
59f28 lwzu    r11,344(r5)
59f2c li      r3,981
59f30 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
59f34 lwz     r2,20(r1)
59f38 lwz     r3,36(r2)   ; TOC+36 -> D_5f00c
59f3c lwz     r5,0(r31)
59f40 lbz     r4,0(r3)
59f44 li      r3,964
59f48 cmplwi  r4,3
59f4c li      r4,8
59f50 bne     0x59f78
59f54 lwzu    r11,344(r5)
59f58 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x8, r5=?)
59f5c lwz     r2,20(r1)
59f60 lwz     r4,0(r31)
59f64 li      r3,965
59f68 lwzu    r11,344(r4)
59f6c li      r4,6
59f70 bl      0x59490   ; SVC out8(r3=0x3c5, r4=0x6, r5=?)
59f74 lwz     r2,20(r1)
59f78 lwz     r12,88(r1)
59f7c lwz     r31,76(r1)
59f80 mtlr    r12
59f84 addic   r1,r1,80
59f88 blr
59f8c .long 0x0
59f90 .long 0x2041
59f94 lwz     r0,256(r1)
59f98 .long 0x0
59f9c .long 0x154
59fa0 .long 0x95333
59fa4 rlwnm   r21,r26,r13,25,22
59fa8 xoris   r3,r27,27392
00059fac <s3_Found>:
59fac stmw    r21,-44(r1)
59fb0 mflr    r0
59fb4 mfcr    r12
59fb8 lwz     r28,4(r2)   ; TOC+4 -> D_60480
59fbc addi    r29,r3,0
59fc0 lwz     r3,0(r28)
59fc4 stw     r12,4(r1)
59fc8 stw     r0,8(r1)
59fcc stwu    r1,-112(r1)
59fd0 li      r31,0
59fd4 lwzu    r11,672(r3)
59fd8 bl      0x59490   ; SVC pci_config_query_slots(r3=?, r4=?, r5=?)
59fdc lwz     r2,20(r1)
59fe0 addic.  r30,r3,-1
59fe4 cmpwi   cr4,r29,0
59fe8 lis     r0,-30544
59fec addic   r25,r0,21299
59ff0 blt     0x5a0c4
59ff4 lis     r0,-30528
59ff8 addic   r22,r0,21299
59ffc lis     r0,-30592
5a000 addic   r26,r0,21299
5a004 lis     r0,-30704
5a008 addic   r23,r0,21299
5a00c lwz     r27,40(r2)   ; TOC+40 -> D_5f010
5a010 li      r24,2
5a014 lwz     r21,36(r2)   ; TOC+36 -> D_5f00c
5a018 li      r29,3
5a01c lwz     r4,0(r28)
5a020 addi    r3,r30,0
5a024 lwzu    r11,684(r4)
5a028 li      r4,0
5a02c bl      0x59490   ; SVC pci_config_read_32(r3=?, r4=0x0, r5=?)
5a030 lwz     r2,20(r1)
5a034 rlwinm  r0,r3,0,16,11
5a038 cmplw   cr1,r0,r25
5a03c cmplw   cr6,r0,r22
5a040 cmpwi   r31,0
5a044 mcrf    cr5,cr6
5a048 beq     cr1,0x5a060
5a04c cmplw   cr1,r0,r26
5a050 beq     cr6,0x5a060
5a054 cmplw   cr6,r0,r23
5a058 beq     cr1,0x5a060
5a05c bne     cr6,0x5a0bc
5a060 cmplw   cr1,r0,r23
5a064 cmplw   cr6,r0,r26
5a068 lwz     r3,0(r28)
5a06c bne     0x5a094
5a070 bne     cr5,0x5a07c
5a074 stb     r24,0(r27)
5a078 stb     r24,0(r21)
5a07c bne     cr6,0x5a088
5a080 stb     r24,0(r27)
5a084 stb     r24,0(r21)
5a088 bne     cr1,0x5a094
5a08c stb     r24,0(r27)
5a090 stb     r29,0(r21)
5a094 beq     cr4,0x5a0b8
5a098 lwzu    r11,696(r3)
5a09c addi    r3,r30,0
5a0a0 li      r4,4
5a0a4 li      r5,0
5a0a8 bne     0x5a0b0
5a0ac li      r5,3
5a0b0 bl      0x59490   ; SVC pci_config_write_32(r3=?, r4=0x4, r5=0x3)
5a0b4 lwz     r2,20(r1)
5a0b8 li      r31,1
5a0bc addic.  r30,r30,-1
5a0c0 bge     0x5a01c
5a0c4 addi    r3,r31,0
5a0c8 lwz     r0,120(r1)
5a0cc lwz     r12,116(r1)
5a0d0 addic   r1,r1,112
5a0d4 mtcrf   8,r12
5a0d8 mtlr    r0
5a0dc lmw     r21,-44(r1)
5a0e0 blr
5a0e4 .long 0x0
5a0e8 .long 0x2043
5a0ec lwz     r0,256(r11)
5a0f0 .long 0x0
5a0f4 .long 0x138
5a0f8 .long 0x87333
5a0fc rlwnm.  r6,r26,r13,29,26
5a100 xoris   r4,r19,0
0005a104 <s3_POS>:
5a104 mflr    r0
5a108 stmw    r29,-12(r1)
5a10c stw     r0,8(r1)
5a110 stwu    r1,-80(r1)
5a114 li      r3,1
5a118 bl      0x59fac  <s3_Found>   ; call s3_Found(r3=0x1, r4=?, r5=?, r6=?)
5a11c cmpwi   cr1,r3,0
5a120 lwz     r6,36(r2)   ; TOC+36 -> D_5f00c
5a124 li      r3,0
5a128 lbz     r0,0(r6)
5a12c beq     cr1,0x5a570
5a130 cmplwi  cr1,r0,3
5a134 lwz     r31,4(r2)   ; TOC+4 -> D_60480
5a138 li      r0,0
5a13c lwz     r6,0(r31)
5a140 lwz     r30,44(r2)   ; TOC+44 -> D_5f014
5a144 bne     cr1,0x5a1d8
5a148 stw     r0,3832(r30)
5a14c lwzu    r11,324(r6)
5a150 li      r3,972
5a154 bl      0x59490   ; SVC in8(r3=0x3cc, r4=?, r5=?)
5a158 lwz     r2,20(r1)
5a15c cmplwi  cr1,r3,255
5a160 lwz     r6,0(r31)
5a164 li      r4,1
5a168 addi    r7,r6,0
5a16c li      r3,963
5a170 bne     cr1,0x5a1a0
5a174 lwzu    r11,344(r6)
5a178 bl      0x59490   ; SVC out8(r3=0x3c3, r4=0x1, r5=?)
5a17c lwz     r2,20(r1)
5a180 lwz     r6,0(r31)
5a184 li      r3,972
5a188 lwzu    r11,324(r6)
5a18c bl      0x59490   ; SVC in8(r3=0x3cc, r4=?, r5=?)
5a190 lwz     r2,20(r1)
5a194 cmplwi  cr1,r3,255
5a198 beq     cr1,0x5a1d8
5a19c b       0x5a1cc
5a1a0 lwzu    r11,344(r7)
5a1a4 li      r4,0
5a1a8 bl      0x59490   ; SVC out8(r3=?, r4=0x0, r5=?)
5a1ac lwz     r2,20(r1)
5a1b0 lwz     r6,0(r31)
5a1b4 li      r3,972
5a1b8 lwzu    r11,324(r6)
5a1bc bl      0x59490   ; SVC in8(r3=0x3cc, r4=?, r5=?)
5a1c0 lwz     r2,20(r1)
5a1c4 cmplwi  cr1,r3,255
5a1c8 bne     cr1,0x5a1d8
5a1cc li      r0,1
5a1d0 stw     r0,3832(r30)
5a1d4 b       0x5a1f0
5a1d8 lwz     r0,3832(r30)
5a1dc lwz     r6,0(r31)
5a1e0 cmpwi   cr1,r0,0
5a1e4 li      r3,18152
5a1e8 li      r4,30
5a1ec beq     cr1,0x5a3dc
5a1f0 lwz     r6,0(r31)
5a1f4 li      r3,963
5a1f8 lwzu    r11,344(r6)
5a1fc li      r4,1
5a200 bl      0x59490   ; SVC out8(r3=0x3c3, r4=0x1, r5=?)
5a204 lwz     r2,20(r1)
5a208 lwz     r6,0(r31)
5a20c li      r3,972
5a210 lwzu    r11,324(r6)
5a214 bl      0x59490   ; SVC in8(r3=0x3cc, r4=?, r5=?)
5a218 lwz     r2,20(r1)
5a21c lwz     r6,0(r31)
5a220 clrlwi  r0,r3,24
5a224 ori     r29,r0,13
5a228 lwzu    r11,344(r6)
5a22c li      r3,962
5a230 addi    r4,r29,0
5a234 bl      0x59490   ; SVC out8(r3=0x3c2, r4=?, r5=?)
5a238 lwz     r2,20(r1)
5a23c bl      0x59e38  <S3_Unlock>   ; call S3_Unlock(r3=?, r4=?, r5=?, r6=?)
5a240 lwz     r6,0(r31)
5a244 li      r3,964
5a248 lwzu    r11,356(r6)
5a24c li      r4,18706
5a250 bl      0x59490   ; SVC out16le(r3=0x3c4, r4=0x4912, r5=?)
5a254 lwz     r2,20(r1)
5a258 lwz     r6,0(r31)
5a25c li      r3,964
5a260 lwzu    r11,356(r6)
5a264 li      r4,21779
5a268 bl      0x59490   ; SVC out16le(r3=0x3c4, r4=0x5513, r5=?)
5a26c lwz     r2,20(r1)
5a270 lwz     r6,0(r31)
5a274 li      r3,964
5a278 lwzu    r11,356(r6)
5a27c li      r4,16912
5a280 bl      0x59490   ; SVC out16le(r3=0x3c4, r4=0x4210, r5=?)
5a284 lwz     r2,20(r1)
5a288 lwz     r6,0(r31)
5a28c li      r3,964
5a290 lwzu    r11,356(r6)
5a294 li      r4,16657
5a298 bl      0x59490   ; SVC out16le(r3=0x3c4, r4=0x4111, r5=?)
5a29c lwz     r2,20(r1)
5a2a0 lwz     r6,0(r31)
5a2a4 addi    r4,r29,0
5a2a8 lwzu    r11,344(r6)
5a2ac li      r3,964
5a2b0 bl      0x59490   ; SVC out8(r3=0x3c4, r4=?, r5=?)
5a2b4 lwz     r2,20(r1)
5a2b8 lwz     r6,0(r31)
5a2bc li      r3,964
5a2c0 lwzu    r11,356(r6)
5a2c4 li      r4,788
5a2c8 bl      0x59490   ; SVC out16le(r3=0x3c4, r4=0x314, r5=?)
5a2cc lwz     r2,20(r1)
5a2d0 lwz     r6,0(r31)
5a2d4 lis     r0,-15
5a2d8 addic   r29,r0,-16960
5a2dc lwzu    r11,448(r6)
5a2e0 li      r3,5
5a2e4 addi    r4,r29,0
5a2e8 bl      0x59490   ; SVC sleep(r3=0x5, r4=0xfff0bdc0, r5=?)
5a2ec lwz     r2,20(r1)
5a2f0 lwz     r6,0(r31)
5a2f4 li      r3,964
5a2f8 lwzu    r11,356(r6)
5a2fc li      r4,20
5a300 bl      0x59490   ; SVC out16le(r3=0x3c4, r4=0x14, r5=?)
5a304 lwz     r2,20(r1)
5a308 lwz     r6,0(r31)
5a30c addi    r4,r29,0
5a310 lwzu    r11,448(r6)
5a314 li      r3,1
5a318 bl      0x59490   ; SVC sleep(r3=0x1, r4=0xfff0bdc0, r5=?)
5a31c lwz     r2,20(r1)
5a320 lwz     r6,0(r31)
5a324 li      r3,980
5a328 lwzu    r11,344(r6)
5a32c li      r4,54
5a330 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x36, r5=?)
5a334 lwz     r2,20(r1)
5a338 lwz     r6,0(r31)
5a33c li      r3,981
5a340 lwzu    r11,324(r6)
5a344 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5a348 lwz     r2,20(r1)
5a34c lwz     r0,3832(r30)
5a350 rlwinm. r6,r3,0,28,29
5a354 cmpwi   cr1,r0,1
5a358 bne     cr1,0x5a390
5a35c lwz     r6,0(r31)
5a360 li      r3,964
5a364 li      r4,17424
5a368 bne     0x5a390
5a36c lwzu    r11,356(r6)
5a370 bl      0x59490   ; SVC out16le(r3=0x3c4, r4=0x4410, r5=?)
5a374 lwz     r2,20(r1)
5a378 lwz     r6,0(r31)
5a37c li      r3,964
5a380 lwzu    r11,356(r6)
5a384 li      r4,16657
5a388 bl      0x59490   ; SVC out16le(r3=0x3c4, r4=0x4111, r5=?)
5a38c lwz     r2,20(r1)
5a390 lwz     r6,0(r31)
5a394 li      r3,964
5a398 lwzu    r11,356(r6)
5a39c li      r4,16408
5a3a0 bl      0x59490   ; SVC out16le(r3=0x3c4, r4=0x4018, r5=?)
5a3a4 lwz     r2,20(r1)
5a3a8 lwz     r6,0(r31)
5a3ac li      r3,964
5a3b0 lwzu    r11,356(r6)
5a3b4 li      r4,21
5a3b8 bl      0x59490   ; SVC out16le(r3=0x3c4, r4=0x15, r5=?)
5a3bc lwz     r2,20(r1)
5a3c0 lwz     r6,0(r31)
5a3c4 li      r3,964
5a3c8 lwzu    r11,356(r6)
5a3cc li      r4,789
5a3d0 bl      0x59490   ; SVC out16le(r3=0x3c4, r4=0x315, r5=?)
5a3d4 lwz     r2,20(r1)
5a3d8 b       0x5a464
5a3dc lwzu    r11,344(r6)
5a3e0 bl      0x59490   ; SVC out8(r3=?, r4=?, r5=?)
5a3e4 lwz     r2,20(r1)
5a3e8 lwz     r6,0(r31)
5a3ec li      r3,258
5a3f0 lwzu    r11,344(r6)
5a3f4 li      r4,1
5a3f8 bl      0x59490   ; SVC out8(r3=0x102, r4=0x1, r5=?)
5a3fc lwz     r2,20(r1)
5a400 lwz     r6,0(r31)
5a404 li      r3,19176
5a408 lwzu    r11,356(r6)
5a40c li      r4,0
5a410 bl      0x59490   ; SVC out16le(r3=0x4ae8, r4=0x0, r5=?)
5a414 lwz     r2,20(r1)
5a418 lwz     r6,0(r31)
5a41c li      r3,18152
5a420 lwzu    r11,344(r6)
5a424 li      r4,14
5a428 bl      0x59490   ; SVC out8(r3=0x46e8, r4=0xe, r5=?)
5a42c lwz     r2,20(r1)
5a430 lwz     r6,0(r31)
5a434 li      r3,972
5a438 lwzu    r11,324(r6)
5a43c bl      0x59490   ; SVC in8(r3=0x3cc, r4=?, r5=?)
5a440 lwz     r2,20(r1)
5a444 lwz     r6,0(r31)
5a448 clrlwi  r0,r3,24
5a44c ori     r4,r0,13
5a450 lwzu    r11,344(r6)
5a454 li      r3,962
5a458 bl      0x59490   ; SVC out8(r3=0x3c2, r4=?, r5=?)
5a45c lwz     r2,20(r1)
5a460 bl      0x59e38  <S3_Unlock>   ; call S3_Unlock(r3=?, r4=?, r5=?, r6=?)
5a464 lwz     r6,0(r31)
5a468 lis     r4,0
5a46c ori     r4,r4,32768
5a470 lwzu    r11,356(r6)
5a474 li      r3,17128
5a478 bl      0x59490   ; SVC out16le(r3=0x42e8, r4=0x8000, r5=?)
5a47c lwz     r2,20(r1)
5a480 bl      0x5cc68  <ge_wait>   ; call ge_wait(r3=?, r4=?, r5=?, r6=?)
5a484 lwz     r6,0(r31)
5a488 li      r3,17128
5a48c lwzu    r11,356(r6)
5a490 li      r4,16384
5a494 bl      0x59490   ; SVC out16le(r3=0x42e8, r4=0x4000, r5=?)
5a498 lwz     r2,20(r1)
5a49c bl      0x5cc68  <ge_wait>   ; call ge_wait(r3=?, r4=?, r5=?, r6=?)
5a4a0 lwz     r6,0(r31)
5a4a4 li      r3,980
5a4a8 lwzu    r11,344(r6)
5a4ac li      r4,64
5a4b0 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x40, r5=?)
5a4b4 lwz     r2,20(r1)
5a4b8 lwz     r6,0(r31)
5a4bc li      r3,981
5a4c0 lwzu    r11,344(r6)
5a4c4 li      r4,0
5a4c8 bl      0x59490   ; SVC out8(r3=0x3d5, r4=0x0, r5=?)
5a4cc lwz     r2,20(r1)
5a4d0 lwz     r7,40(r2)   ; TOC+40 -> D_5f010
5a4d4 lwz     r6,0(r31)
5a4d8 lbz     r0,0(r7)
5a4dc li      r3,980
5a4e0 cmpwi   cr1,r0,0
5a4e4 li      r4,85
5a4e8 bne     cr1,0x5a56c
5a4ec lwzu    r11,344(r6)
5a4f0 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x55, r5=?)
5a4f4 lwz     r2,20(r1)
5a4f8 lwz     r6,0(r31)
5a4fc li      r3,981
5a500 lwzu    r11,324(r6)
5a504 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5a508 lwz     r2,20(r1)
5a50c lwz     r6,0(r31)
5a510 clrlwi  r30,r3,24
5a514 lwzu    r11,344(r6)
5a518 ori     r4,r30,4
5a51c li      r3,981
5a520 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5a524 lwz     r2,20(r1)
5a528 lwz     r6,0(r31)
5a52c li      r3,968
5a530 lwzu    r11,324(r6)
5a534 bl      0x59490   ; SVC in8(r3=0x3c8, r4=?, r5=?)
5a538 lwz     r2,20(r1)
5a53c srwi    r0,r3,4
5a540 mtcrf   1,r0
5a544 lwz     r6,0(r31)
5a548 addi    r4,r30,0
5a54c li      r3,981
5a550 bns     cr7,0x5a560
5a554 lwz     r7,48(r2)   ; TOC+48 -> D_5ff1c
5a558 li      r0,1
5a55c stb     r0,0(r7)
5a560 lwzu    r11,344(r6)
5a564 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5a568 lwz     r2,20(r1)
5a56c li      r3,1
5a570 lwz     r12,88(r1)
5a574 addic   r1,r1,80
5a578 mtlr    r12
5a57c lmw     r29,-12(r1)
5a580 blr
5a584 .long 0x0
5a588 .long 0x2041
5a58c lwz     r0,256(r3)
5a590 .long 0x0
5a594 .long 0x480
5a598 .long 0x67333
5a59c rlwnm.  r16,r26,r9,29,9
0005a5a0 <Async_Reset>:
5a5a0 stmw    r30,-8(r1)
5a5a4 mflr    r0
5a5a8 lwz     r30,4(r2)   ; TOC+4 -> D_60480
5a5ac stw     r0,8(r1)
5a5b0 lwz     r5,0(r30)
5a5b4 stwu    r1,-80(r1)
5a5b8 li      r3,964
5a5bc li      r4,1
5a5c0 lwzu    r11,344(r5)
5a5c4 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x1, r5=?)
5a5c8 lwz     r2,20(r1)
5a5cc lwz     r4,0(r30)
5a5d0 li      r3,965
5a5d4 lwzu    r11,344(r4)
5a5d8 li      r4,32
5a5dc bl      0x59490   ; SVC out8(r3=0x3c5, r4=0x20, r5=?)
5a5e0 lwz     r2,20(r1)
5a5e4 lwz     r4,0(r30)
5a5e8 li      r3,964
5a5ec lwzu    r11,344(r4)
5a5f0 li      r4,0
5a5f4 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x0, r5=?)
5a5f8 lwz     r2,20(r1)
5a5fc lwz     r4,0(r30)
5a600 li      r3,965
5a604 lwzu    r11,344(r4)
5a608 li      r4,0
5a60c bl      0x59490   ; SVC out8(r3=0x3c5, r4=0x0, r5=?)
5a610 lwz     r2,20(r1)
5a614 lwz     r4,0(r30)
5a618 li      r3,964
5a61c lwzu    r11,344(r4)
5a620 li      r4,0
5a624 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x0, r5=?)
5a628 lwz     r2,20(r1)
5a62c lwz     r4,0(r30)
5a630 li      r3,965
5a634 lwzu    r11,344(r4)
5a638 li      r4,3
5a63c bl      0x59490   ; SVC out8(r3=0x3c5, r4=0x3, r5=?)
5a640 lwz     r2,20(r1)
5a644 lwz     r4,0(r30)
5a648 li      r3,964
5a64c lwzu    r11,344(r4)
5a650 li      r4,1
5a654 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x1, r5=?)
5a658 lwz     r2,20(r1)
5a65c lwz     r4,0(r30)
5a660 li      r3,965
5a664 lwzu    r11,324(r4)
5a668 bl      0x59490   ; SVC in8(r3=0x3c5, r4=?, r5=?)
5a66c lwz     r2,20(r1)
5a670 lwz     r4,0(r30)
5a674 andi.   r31,r3,223
5a678 lwzu    r11,344(r4)
5a67c li      r3,964
5a680 li      r4,1
5a684 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x1, r5=?)
5a688 lwz     r2,20(r1)
5a68c lwz     r3,0(r30)
5a690 addi    r4,r31,0
5a694 lwzu    r11,344(r3)
5a698 li      r3,965
5a69c bl      0x59490   ; SVC out8(r3=0x3c5, r4=?, r5=?)
5a6a0 lwz     r2,20(r1)
5a6a4 lwz     r12,88(r1)
5a6a8 addic   r1,r1,80
5a6ac mtlr    r12
5a6b0 lmw     r30,-8(r1)
5a6b4 blr
5a6b8 .long 0x0
5a6bc .long 0x2041
5a6c0 lwz     r0,256(r2)   ; TOC+256 -> D_58f1c
5a6c4 .long 0x0
5a6c8 .long 0x118
5a6cc .long 0xb4173
5a6d0 .long 0x796e635f
5a6d4 rlwimi. r5,r19,14,13,18
5a6d8 andis.  r0,r0,0
0005a6dc <dac_init>:
5a6dc stmw    r29,-12(r1)
5a6e0 mflr    r0
5a6e4 lwz     r31,4(r2)   ; TOC+4 -> D_60480
5a6e8 stw     r0,8(r1)
5a6ec lwz     r8,0(r31)
5a6f0 addi    r30,r3,0
5a6f4 stwu    r1,-80(r1)
5a6f8 li      r3,966
5a6fc li      r4,255
5a700 lwzu    r11,344(r8)
5a704 bl      0x59490   ; SVC out8(r3=0x3c6, r4=0xff, r5=?)
5a708 lwz     r2,20(r1)
5a70c lwz     r4,36(r2)   ; TOC+36 -> D_5f00c
5a710 lbz     r0,0(r4)
5a714 cmpwi   cr6,r0,0
5a718 cmplwi  r0,2
5a71c cmplwi  cr1,r0,1
5a720 bne     cr6,0x5a858
5a724 lwz     r4,44(r2)   ; TOC+44 -> D_5f014
5a728 lis     r0,256
5a72c lwz     r4,3808(r4)
5a730 addic   r3,r0,966
5a734 lbz     r0,12(r4)
5a738 cmplwi  cr6,r0,8
5a73c cmplwi  cr1,r0,32
5a740 cmplwi  r0,16
5a744 bne     cr6,0x5a7c4
5a748 li      r4,130
5a74c bl      0x5adf4  <s3_bt485_write>   ; call s3_bt485_write(r3=0x10003c6, r4=0x82, r5=?, r6=?)
5a750 lwz     r4,0(r31)
5a754 li      r3,968
5a758 lwzu    r11,344(r4)
5a75c li      r4,1
5a760 bl      0x59490   ; SVC out8(r3=0x3c8, r4=0x1, r5=?)
5a764 lwz     r2,20(r1)
5a768 lbz     r0,0(r30)
5a76c lis     r31,512
5a770 mtcrf   1,r0
5a774 addic   r3,r31,966
5a778 bns     cr7,0x5a7a0
5a77c li      r4,8
5a780 bl      0x5adf4  <s3_bt485_write>   ; call s3_bt485_write(r3=0x20003c6, r4=0x8, r5=?, r6=?)
5a784 addic   r3,r31,968
5a788 li      r4,64
5a78c bl      0x5adf4  <s3_bt485_write>   ; call s3_bt485_write(r3=0x20003c8, r4=0x40, r5=?, r6=?)
5a790 addic   r3,r31,969
5a794 li      r4,34
5a798 bl      0x5adf4  <s3_bt485_write>   ; call s3_bt485_write(r3=0x20003c9, r4=0x22, r5=?, r6=?)
5a79c b       0x5acf0
5a7a0 li      r4,0
5a7a4 bl      0x5adf4  <s3_bt485_write>   ; call s3_bt485_write(r3=?, r4=0x0, r5=?, r6=?)
5a7a8 addic   r3,r31,968
5a7ac li      r4,0
5a7b0 bl      0x5adf4  <s3_bt485_write>   ; call s3_bt485_write(r3=0x20003c8, r4=0x0, r5=?, r6=?)
5a7b4 addic   r3,r31,969
5a7b8 li      r4,2
5a7bc bl      0x5adf4  <s3_bt485_write>   ; call s3_bt485_write(r3=0x20003c9, r4=0x2, r5=?, r6=?)
5a7c0 b       0x5acf0
5a7c4 lis     r0,256
5a7c8 addic   r29,r0,966
5a7cc bne     0x5a828
5a7d0 li      r4,130
5a7d4 bl      0x5adf4  <s3_bt485_write>   ; call s3_bt485_write(r3=?, r4=0x82, r5=?, r6=?)
5a7d8 lis     r30,512
5a7dc addic   r3,r30,968
5a7e0 li      r4,56
5a7e4 bl      0x5adf4  <s3_bt485_write>   ; call s3_bt485_write(r3=0x20003c8, r4=0x38, r5=?, r6=?)
5a7e8 addic   r3,r30,969
5a7ec li      r4,34
5a7f0 bl      0x5adf4  <s3_bt485_write>   ; call s3_bt485_write(r3=0x20003c9, r4=0x22, r5=?, r6=?)
5a7f4 lwz     r4,0(r31)
5a7f8 li      r3,968
5a7fc lwzu    r11,344(r4)
5a800 li      r4,1
5a804 bl      0x59490   ; SVC out8(r3=0x3c8, r4=0x1, r5=?)
5a808 lwz     r2,20(r1)
5a80c addic   r3,r30,966
5a810 li      r4,8
5a814 bl      0x5adf4  <s3_bt485_write>   ; call s3_bt485_write(r3=0x20003c6, r4=0x8, r5=?, r6=?)
5a818 addi    r3,r29,0
5a81c li      r4,2
5a820 bl      0x5adf4  <s3_bt485_write>   ; call s3_bt485_write(r3=0x10003c6, r4=0x2, r5=?, r6=?)
5a824 b       0x5acf0
5a828 addic   r3,r0,966
5a82c bne     cr1,0x5acf0
5a830 li      r4,2
5a834 bl      0x5adf4  <s3_bt485_write>   ; call s3_bt485_write(r3=?, r4=0x2, r5=?, r6=?)
5a838 lis     r31,512
5a83c addic   r3,r31,968
5a840 li      r4,16
5a844 bl      0x5adf4  <s3_bt485_write>   ; call s3_bt485_write(r3=0x20003c8, r4=0x10, r5=?, r6=?)
5a848 addic   r3,r31,969
5a84c li      r4,34
5a850 bl      0x5adf4  <s3_bt485_write>   ; call s3_bt485_write(r3=0x20003c9, r4=0x22, r5=?, r6=?)
5a854 b       0x5acf0
5a858 bne     cr1,0x5a8d8
5a85c lwz     r31,44(r2)   ; TOC+44 -> D_5f014
5a860 lbz     r3,0(r31)
5a864 cmpwi   cr1,r3,0
5a868 beq     cr1,0x5a880
5a86c lbz     r4,1(r31)
5a870 bl      0x5b198  <s3_rgb525_write>   ; call s3_rgb525_write(r3=?, r4=?, r5=?, r6=?)
5a874 lbzu    r3,2(r31)
5a878 cmpwi   cr1,r3,0
5a87c bne     cr1,0x5a86c
5a880 lbz     r4,0(r30)
5a884 cmplwi  r4,128
5a888 cmplwi  cr1,r4,131
5a88c blt     0x5a8b0
5a890 bgt     cr1,0x5a8b0
5a894 li      r3,113
5a898 bl      0x5b098  <s3_rgb525_read>   ; call s3_rgb525_read(r3=0x71, r4=?, r5=?, r6=?)
5a89c andi.   r0,r3,191
5a8a0 ori     r4,r0,128
5a8a4 li      r3,113
5a8a8 bl      0x5b198  <s3_rgb525_write>   ; call s3_rgb525_write(r3=0x71, r4=?, r5=?, r6=?)
5a8ac lbz     r4,0(r30)
5a8b0 li      r3,32
5a8b4 bl      0x5b198  <s3_rgb525_write>   ; call s3_rgb525_write(r3=0x20, r4=?, r5=?, r6=?)
5a8b8 addi    r8,r30,0
5a8bc lbzu    r4,2(r8)
5a8c0 li      r3,10
5a8c4 bl      0x5b198  <s3_rgb525_write>   ; call s3_rgb525_write(r3=0xa, r4=?, r5=?, r6=?)
5a8c8 lbzu    r4,1(r30)
5a8cc li      r3,2
5a8d0 bl      0x5b198  <s3_rgb525_write>   ; call s3_rgb525_write(r3=0x2, r4=?, r5=?, r6=?)
5a8d4 b       0x5acf0
5a8d8 bne     0x5a934
5a8dc lbz     r4,0(r30)
5a8e0 li      r3,966
5a8e4 bl      0x5aec4  <s3_sdac_write>   ; call s3_sdac_write(r3=0x3c6, r4=?, r5=?, r6=?)
5a8e8 addic   r31,r30,1
5a8ec li      r29,2
5a8f0 addic   r30,r30,2
5a8f4 lbz     r4,0(r31)
5a8f8 lbz     r5,0(r30)
5a8fc addi    r3,r29,0
5a900 bl      0x5af90  <s3_sdac_write2>   ; call s3_sdac_write2(r3=0x2, r4=?, r5=?, r6=?)
5a904 addic   r29,r29,1
5a908 cmpwi   cr1,r29,8
5a90c blt     cr1,0x5a8f4
5a910 li      r3,10
5a914 li      r4,65
5a918 li      r5,66
5a91c bl      0x5af90  <s3_sdac_write2>   ; call s3_sdac_write2(r3=0xa, r4=0x41, r5=0x42, r6=?)
5a920 li      r3,14
5a924 li      r4,34
5a928 li      r5,0
5a92c bl      0x5af90  <s3_sdac_write2>   ; call s3_sdac_write2(r3=0xe, r4=0x22, r5=0x0, r6=?)
5a930 b       0x5acf0
5a934 lwz     r4,0(r31)
5a938 li      r3,972
5a93c lwzu    r11,324(r4)
5a940 bl      0x59490   ; SVC in8(r3=0x3cc, r4=?, r5=?)
5a944 lwz     r2,20(r1)
5a948 lwz     r4,0(r31)
5a94c clrlwi  r0,r3,24
5a950 lwzu    r11,344(r4)
5a954 ori     r4,r0,12
5a958 li      r3,962
5a95c bl      0x59490   ; SVC out8(r3=0x3c2, r4=?, r5=?)
5a960 lwz     r2,20(r1)
5a964 lwz     r4,0(r31)
5a968 li      r3,964
5a96c lwzu    r11,344(r4)
5a970 li      r4,21
5a974 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x15, r5=?)
5a978 lwz     r2,20(r1)
5a97c lwz     r4,0(r31)
5a980 li      r3,965
5a984 addi    r8,r4,0
5a988 lwzu    r29,344(r8)
5a98c lwzu    r11,324(r4)
5a990 bl      0x59490   ; SVC in8(r3=0x3c5, r4=?, r5=?)
5a994 lwz     r2,20(r1)
5a998 li      r0,-36
5a99c and     r4,r3,r0
5a9a0 addi    r11,r29,0
5a9a4 li      r3,965
5a9a8 bl      0x59490   ; SVC out8(r3=0x3c5, r4=?, r5=?)
5a9ac lwz     r2,20(r1)
5a9b0 lwz     r4,0(r31)
5a9b4 li      r3,964
5a9b8 lwzu    r11,344(r4)
5a9bc li      r4,11
5a9c0 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0xb, r5=?)
5a9c4 lwz     r2,20(r1)
5a9c8 lwz     r8,0(r31)
5a9cc lbz     r4,0(r30)
5a9d0 lwzu    r11,344(r8)
5a9d4 li      r3,965
5a9d8 bl      0x59490   ; SVC out8(r3=0x3c5, r4=?, r5=?)
5a9dc lwz     r2,20(r1)
5a9e0 lwz     r4,0(r31)
5a9e4 li      r3,964
5a9e8 lwzu    r11,344(r4)
5a9ec li      r4,27
5a9f0 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x1b, r5=?)
5a9f4 lwz     r2,20(r1)
5a9f8 lwz     r4,0(r31)
5a9fc li      r3,965
5aa00 lwzu    r11,344(r4)
5aa04 li      r4,0
5aa08 bl      0x59490   ; SVC out8(r3=0x3c5, r4=0x0, r5=?)
5aa0c lwz     r2,20(r1)
5aa10 lwz     r4,0(r31)
5aa14 li      r3,964
5aa18 lwzu    r11,344(r4)
5aa1c li      r4,26
5aa20 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x1a, r5=?)
5aa24 lwz     r2,20(r1)
5aa28 lwz     r4,0(r31)
5aa2c li      r3,965
5aa30 lwzu    r11,344(r4)
5aa34 li      r4,66
5aa38 bl      0x59490   ; SVC out8(r3=0x3c5, r4=0x42, r5=?)
5aa3c lwz     r2,20(r1)
5aa40 lwz     r4,0(r31)
5aa44 li      r3,964
5aa48 lwzu    r11,344(r4)
5aa4c li      r4,20
5aa50 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x14, r5=?)
5aa54 lwz     r2,20(r1)
5aa58 lwz     r4,0(r31)
5aa5c li      r3,965
5aa60 lwzu    r11,344(r4)
5aa64 li      r4,0
5aa68 bl      0x59490   ; SVC out8(r3=0x3c5, r4=0x0, r5=?)
5aa6c lwz     r2,20(r1)
5aa70 lwz     r4,0(r31)
5aa74 li      r3,964
5aa78 lwzu    r11,344(r4)
5aa7c li      r4,9
5aa80 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x9, r5=?)
5aa84 lwz     r2,20(r1)
5aa88 lwz     r4,0(r31)
5aa8c li      r3,965
5aa90 lwzu    r11,344(r4)
5aa94 li      r4,2
5aa98 bl      0x59490   ; SVC out8(r3=0x3c5, r4=0x2, r5=?)
5aa9c lwz     r2,20(r1)
5aaa0 lwz     r4,0(r31)
5aaa4 li      r3,964
5aaa8 lwzu    r11,344(r4)
5aaac li      r4,21
5aab0 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x15, r5=?)
5aab4 lwz     r2,20(r1)
5aab8 lwz     r4,0(r31)
5aabc li      r3,965
5aac0 addi    r8,r4,0
5aac4 lwzu    r29,344(r8)
5aac8 lwzu    r11,324(r4)
5aacc bl      0x59490   ; SVC in8(r3=0x3c5, r4=?, r5=?)
5aad0 lwz     r2,20(r1)
5aad4 li      r0,-228
5aad8 and     r4,r3,r0
5aadc addi    r11,r29,0
5aae0 li      r3,965
5aae4 bl      0x59490   ; SVC out8(r3=0x3c5, r4=?, r5=?)
5aae8 lwz     r2,20(r1)
5aaec lwz     r4,0(r31)
5aaf0 li      r3,964
5aaf4 lwzu    r11,344(r4)
5aaf8 li      r4,24
5aafc bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x18, r5=?)
5ab00 lwz     r2,20(r1)
5ab04 lwz     r4,0(r31)
5ab08 li      r3,965
5ab0c lwzu    r11,324(r4)
5ab10 bl      0x59490   ; SVC in8(r3=0x3c5, r4=?, r5=?)
5ab14 lwz     r2,20(r1)
5ab18 lwz     r8,0(r31)
5ab1c clrlwi  r0,r3,25
5ab20 ori     r4,r0,64
5ab24 lwzu    r11,344(r8)
5ab28 li      r3,965
5ab2c bl      0x59490   ; SVC out8(r3=0x3c5, r4=?, r5=?)
5ab30 lwz     r2,20(r1)
5ab34 lbz     r0,0(r30)
5ab38 rlwinm  r0,r0,0,24,27
5ab3c cmplwi  cr1,r0,16
5ab40 bne     cr1,0x5abd4
5ab44 lwz     r4,0(r31)
5ab48 li      r3,964
5ab4c lwzu    r11,344(r4)
5ab50 li      r4,21
5ab54 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x15, r5=?)
5ab58 lwz     r2,20(r1)
5ab5c lwz     r4,0(r31)
5ab60 li      r3,965
5ab64 addi    r8,r4,0
5ab68 lwzu    r29,344(r8)
5ab6c lwzu    r11,324(r4)
5ab70 bl      0x59490   ; SVC in8(r3=0x3c5, r4=?, r5=?)
5ab74 lwz     r2,20(r1)
5ab78 ori     r4,r3,16
5ab7c addi    r11,r29,0
5ab80 li      r3,965
5ab84 bl      0x59490   ; SVC out8(r3=0x3c5, r4=?, r5=?)
5ab88 lwz     r2,20(r1)
5ab8c lwz     r4,0(r31)
5ab90 li      r3,964
5ab94 lwzu    r11,344(r4)
5ab98 li      r4,24
5ab9c bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x18, r5=?)
5aba0 lwz     r2,20(r1)
5aba4 lwz     r4,0(r31)
5aba8 li      r3,965
5abac addi    r8,r4,0
5abb0 lwzu    r29,344(r8)
5abb4 lwzu    r11,324(r4)
5abb8 bl      0x59490   ; SVC in8(r3=0x3c5, r4=?, r5=?)
5abbc lwz     r2,20(r1)
5abc0 ori     r4,r3,128
5abc4 addi    r11,r29,0
5abc8 li      r3,965
5abcc bl      0x59490   ; SVC out8(r3=0x3c5, r4=?, r5=?)
5abd0 lwz     r2,20(r1)
5abd4 lwz     r4,0(r31)
5abd8 li      r3,964
5abdc lwzu    r11,344(r4)
5abe0 li      r4,18
5abe4 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x12, r5=?)
5abe8 lwz     r2,20(r1)
5abec lwz     r4,0(r31)
5abf0 addi    r8,r30,0
5abf4 lwzu    r11,344(r4)
5abf8 lbzu    r4,2(r8)
5abfc li      r3,965
5ac00 bl      0x59490   ; SVC out8(r3=0x3c5, r4=?, r5=?)
5ac04 lwz     r2,20(r1)
5ac08 lwz     r4,0(r31)
5ac0c li      r3,964
5ac10 lwzu    r11,344(r4)
5ac14 li      r4,19
5ac18 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x13, r5=?)
5ac1c lwz     r2,20(r1)
5ac20 lwz     r8,0(r31)
5ac24 lbzu    r4,1(r30)
5ac28 lwzu    r11,344(r8)
5ac2c li      r3,965
5ac30 bl      0x59490   ; SVC out8(r3=0x3c5, r4=?, r5=?)
5ac34 lwz     r2,20(r1)
5ac38 lwz     r4,0(r31)
5ac3c li      r3,980
5ac40 lwzu    r11,344(r4)
5ac44 li      r4,54
5ac48 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x36, r5=?)
5ac4c lwz     r2,20(r1)
5ac50 lwz     r4,0(r31)
5ac54 li      r3,981
5ac58 lwzu    r11,324(r4)
5ac5c bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5ac60 lwz     r2,20(r1)
5ac64 lwz     r4,44(r2)   ; TOC+44 -> D_5f014
5ac68 rlwinm. r0,r3,0,28,29
5ac6c lwz     r4,3832(r4)
5ac70 cmpwi   cr1,r4,0
5ac74 beq     cr1,0x5ac7c
5ac78 beq     0x5ac90
5ac7c lwz     r4,0(r31)
5ac80 li      r3,964
5ac84 lwzu    r11,356(r4)
5ac88 li      r4,16912
5ac8c b       0x5aca0
5ac90 lwz     r4,0(r31)
5ac94 li      r3,964
5ac98 lwzu    r11,356(r4)
5ac9c li      r4,17424
5aca0 bl      0x59490   ; SVC out16le(r3=0x3c4, r4=0x4410, r5=?)
5aca4 lwz     r2,20(r1)
5aca8 lwz     r4,0(r31)
5acac li      r3,964
5acb0 lwzu    r11,356(r4)
5acb4 li      r4,16657
5acb8 bl      0x59490   ; SVC out16le(r3=0x3c4, r4=0x4111, r5=?)
5acbc lwz     r2,20(r1)
5acc0 lwz     r4,0(r31)
5acc4 li      r3,964
5acc8 lwzu    r11,356(r4)
5accc li      r4,21
5acd0 bl      0x59490   ; SVC out16le(r3=0x3c4, r4=0x15, r5=?)
5acd4 lwz     r2,20(r1)
5acd8 lwz     r4,0(r31)
5acdc li      r3,964
5ace0 lwzu    r11,356(r4)
5ace4 li      r4,789
5ace8 bl      0x59490   ; SVC out16le(r3=0x3c4, r4=0x315, r5=?)
5acec lwz     r2,20(r1)
5acf0 lwz     r12,88(r1)
5acf4 addic   r1,r1,80
5acf8 mtlr    r12
5acfc lmw     r29,-12(r1)
5ad00 blr
5ad04 .long 0x0
5ad08 .long 0x2041
5ad0c lwz     r0,256(r3)
5ad10 .long 0x0
5ad14 .long 0x628
5ad18 .long 0x86461
5ad1c ori     r31,r26,26990
5ad20 xori    r20,r11,0
0005ad24 <s3_bt485_read>:
5ad24 stmw    r28,-16(r1)
5ad28 mflr    r0
5ad2c lwz     r30,4(r2)   ; TOC+4 -> D_60480
5ad30 stw     r0,8(r1)
5ad34 lwz     r7,0(r30)
5ad38 srwi    r29,r3,24
5ad3c clrlwi  r31,r3,20
5ad40 stwu    r1,-80(r1)
5ad44 li      r3,980
5ad48 lwzu    r11,344(r7)
5ad4c li      r4,85
5ad50 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x55, r5=?)
5ad54 lwz     r2,20(r1)
5ad58 lwz     r7,0(r30)
5ad5c li      r3,981
5ad60 lwzu    r11,324(r7)
5ad64 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5ad68 lwz     r2,20(r1)
5ad6c lwz     r7,0(r30)
5ad70 rlwinm  r28,r3,0,24,29
5ad74 lwzu    r11,344(r7)
5ad78 or      r4,r28,r29
5ad7c li      r3,981
5ad80 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5ad84 lwz     r2,20(r1)
5ad88 lwz     r7,0(r30)
5ad8c addi    r3,r31,0
5ad90 lwzu    r11,324(r7)
5ad94 bl      0x59490   ; SVC in8(r3=?, r4=?, r5=?)
5ad98 lwz     r2,20(r1)
5ad9c lwz     r7,0(r30)
5ada0 clrlwi  r31,r3,24
5ada4 lwzu    r11,344(r7)
5ada8 addi    r4,r28,0
5adac li      r3,981
5adb0 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5adb4 lwz     r2,20(r1)
5adb8 addi    r3,r31,0
5adbc lwz     r12,88(r1)
5adc0 addic   r1,r1,80
5adc4 mtlr    r12
5adc8 lmw     r28,-16(r1)
5adcc blr
5add0 .long 0x0
5add4 .long 0x2041
5add8 lwz     r0,256(r4)
5addc .long 0x0
5ade0 .long 0xac
5ade4 .long 0xd7333
5ade8 rlwnm   r2,r27,r14,16,26
5adec addi    r1,r21,24434
5adf0 oris    r1,r11,25600
0005adf4 <s3_bt485_write>:
5adf4 stmw    r27,-20(r1)
5adf8 mflr    r0
5adfc lwz     r31,4(r2)   ; TOC+4 -> D_60480
5ae00 stw     r0,8(r1)
5ae04 lwz     r5,0(r31)
5ae08 clrlwi  r29,r4,24
5ae0c srwi    r30,r3,24
5ae10 clrlwi  r28,r3,16
5ae14 stwu    r1,-96(r1)
5ae18 li      r3,980
5ae1c lwzu    r11,344(r5)
5ae20 li      r4,85
5ae24 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x55, r5=?)
5ae28 lwz     r2,20(r1)
5ae2c lwz     r5,0(r31)
5ae30 li      r3,981
5ae34 lwzu    r11,324(r5)
5ae38 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5ae3c lwz     r2,20(r1)
5ae40 lwz     r5,0(r31)
5ae44 rlwinm  r27,r3,0,24,29
5ae48 lwzu    r11,344(r5)
5ae4c or      r4,r27,r30
5ae50 li      r3,981
5ae54 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5ae58 lwz     r2,20(r1)
5ae5c lwz     r5,0(r31)
5ae60 addi    r3,r28,0
5ae64 lwzu    r11,344(r5)
5ae68 addi    r4,r29,0
5ae6c bl      0x59490   ; SVC out8(r3=?, r4=?, r5=?)
5ae70 lwz     r2,20(r1)
5ae74 lwz     r5,0(r31)
5ae78 addi    r4,r27,0
5ae7c lwzu    r11,344(r5)
5ae80 li      r3,981
5ae84 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5ae88 lwz     r2,20(r1)
5ae8c lwz     r12,104(r1)
5ae90 addic   r1,r1,96
5ae94 mtlr    r12
5ae98 lmw     r27,-20(r1)
5ae9c blr
5aea0 .long 0x0
5aea4 .long 0x2041
5aea8 lwz     r0,512(r5)
5aeac .long 0x0
5aeb0 .long 0xac
5aeb4 .long 0xe7333
5aeb8 rlwnm   r2,r27,r14,16,26
5aebc addi    r1,r21,24439
5aec0 andi.   r9,r19,29797
0005aec4 <s3_sdac_write>:
5aec4 stmw    r29,-12(r1)
5aec8 mflr    r0
5aecc lwz     r31,4(r2)   ; TOC+4 -> D_60480
5aed0 stw     r0,8(r1)
5aed4 lwz     r7,0(r31)
5aed8 stwu    r1,-80(r1)
5aedc stw     r3,56(r1)
5aee0 clrlwi  r30,r4,24
5aee4 li      r3,980
5aee8 li      r4,85
5aeec lwzu    r11,344(r7)
5aef0 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x55, r5=?)
5aef4 lwz     r2,20(r1)
5aef8 lwz     r4,0(r31)
5aefc li      r3,981
5af00 lwzu    r11,324(r4)
5af04 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5af08 lwz     r2,20(r1)
5af0c lwz     r4,0(r31)
5af10 rlwinm  r29,r3,0,24,29
5af14 lwzu    r11,344(r4)
5af18 ori     r4,r29,1
5af1c li      r3,981
5af20 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5af24 lwz     r2,20(r1)
5af28 lwz     r4,0(r31)
5af2c lwz     r3,56(r1)
5af30 lwzu    r11,344(r4)
5af34 addi    r4,r30,0
5af38 bl      0x59490   ; SVC out8(r3=?, r4=?, r5=?)
5af3c lwz     r2,20(r1)
5af40 lwz     r3,0(r31)
5af44 addi    r4,r29,0
5af48 lwzu    r11,344(r3)
5af4c li      r3,981
5af50 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5af54 lwz     r2,20(r1)
5af58 lwz     r12,88(r1)
5af5c addic   r1,r1,80
5af60 mtlr    r12
5af64 lmw     r29,-12(r1)
5af68 blr
5af6c .long 0x0
5af70 .long 0x2041
5af74 lwz     r0,512(r3)
5af78 .long 0x0
5af7c .long 0xa8
5af80 .long 0xd7333
5af84 rlwnm.  r19,r27,r12,17,16
5af88 ori     r31,r26,30578
5af8c xori    r20,r11,25856
0005af90 <s3_sdac_write2>:
5af90 stmw    r27,-20(r1)
5af94 mflr    r0
5af98 lwz     r31,4(r2)   ; TOC+4 -> D_60480
5af9c clrlwi  r30,r5,24
5afa0 lwz     r5,0(r31)
5afa4 stw     r0,8(r1)
5afa8 addi    r28,r3,0
5afac clrlwi  r29,r4,24
5afb0 stwu    r1,-96(r1)
5afb4 li      r3,980
5afb8 li      r4,85
5afbc lwzu    r11,344(r5)
5afc0 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x55, r5=?)
5afc4 lwz     r2,20(r1)
5afc8 lwz     r5,0(r31)
5afcc li      r3,981
5afd0 lwzu    r11,324(r5)
5afd4 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5afd8 lwz     r2,20(r1)
5afdc lwz     r5,0(r31)
5afe0 rlwinm  r27,r3,0,24,29
5afe4 lwzu    r11,344(r5)
5afe8 ori     r4,r27,1
5afec li      r3,981
5aff0 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5aff4 lwz     r2,20(r1)
5aff8 lwz     r5,0(r31)
5affc li      r3,968
5b000 lwzu    r11,344(r5)
5b004 addi    r4,r28,0
5b008 bl      0x59490   ; SVC out8(r3=0x3c8, r4=?, r5=?)
5b00c lwz     r2,20(r1)
5b010 lwz     r5,0(r31)
5b014 addi    r4,r29,0
5b018 lwzu    r11,344(r5)
5b01c li      r3,969
5b020 bl      0x59490   ; SVC out8(r3=0x3c9, r4=?, r5=?)
5b024 lwz     r2,20(r1)
5b028 cmpwi   r28,14
5b02c addi    r4,r30,0
5b030 lwz     r5,0(r31)
5b034 li      r3,969
5b038 bge     0x5b048
5b03c lwzu    r11,344(r5)
5b040 bl      0x59490   ; SVC out8(r3=0x3c9, r4=?, r5=?)
5b044 lwz     r2,20(r1)
5b048 lwz     r5,0(r31)
5b04c addi    r4,r27,0
5b050 lwzu    r11,344(r5)
5b054 li      r3,981
5b058 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5b05c lwz     r2,20(r1)
5b060 lwz     r12,104(r1)
5b064 addic   r1,r1,96
5b068 mtlr    r12
5b06c lmw     r27,-20(r1)
5b070 blr
5b074 .long 0x0
5b078 .long 0x2041
5b07c lwz     r0,768(r5)
5b080 .long 0x0
5b084 .long 0xe4
5b088 .long 0xe7333
5b08c rlwnm.  r19,r27,r12,17,16
5b090 ori     r31,r26,30578
5b094 xori    r20,r11,25906
0005b098 <s3_rgb525_read>:
5b098 stmw    r29,-12(r1)
5b09c mflr    r0
5b0a0 lwz     r31,4(r2)   ; TOC+4 -> D_60480
5b0a4 stw     r0,8(r1)
5b0a8 lwz     r7,0(r31)
5b0ac addi    r30,r3,0
5b0b0 stwu    r1,-80(r1)
5b0b4 li      r3,980
5b0b8 li      r4,85
5b0bc lwzu    r11,344(r7)
5b0c0 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x55, r5=?)
5b0c4 lwz     r2,20(r1)
5b0c8 lwz     r4,0(r31)
5b0cc li      r3,981
5b0d0 lwzu    r11,324(r4)
5b0d4 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5b0d8 lwz     r2,20(r1)
5b0dc lwz     r4,0(r31)
5b0e0 clrlwi  r29,r3,24
5b0e4 lwzu    r11,344(r4)
5b0e8 ori     r4,r29,1
5b0ec li      r3,981
5b0f0 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5b0f4 lwz     r2,20(r1)
5b0f8 lwz     r3,0(r31)
5b0fc clrlwi  r4,r30,24
5b100 lwzu    r11,344(r3)
5b104 li      r3,968
5b108 bl      0x59490   ; SVC out8(r3=0x3c8, r4=?, r5=?)
5b10c lwz     r2,20(r1)
5b110 lwz     r3,0(r31)
5b114 srawi   r4,r30,8
5b118 lwzu    r11,344(r3)
5b11c clrlwi  r4,r4,24
5b120 li      r3,969
5b124 bl      0x59490   ; SVC out8(r3=0x3c9, r4=?, r5=?)
5b128 lwz     r2,20(r1)
5b12c lwz     r4,0(r31)
5b130 li      r3,966
5b134 lwzu    r11,324(r4)
5b138 bl      0x59490   ; SVC in8(r3=0x3c6, r4=?, r5=?)
5b13c lwz     r2,20(r1)
5b140 lwz     r4,0(r31)
5b144 clrlwi  r31,r3,24
5b148 lwzu    r11,344(r4)
5b14c addi    r4,r29,0
5b150 li      r3,981
5b154 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5b158 lwz     r2,20(r1)
5b15c addi    r3,r31,0
5b160 lwz     r12,88(r1)
5b164 addic   r1,r1,80
5b168 mtlr    r12
5b16c lmw     r29,-12(r1)
5b170 blr
5b174 .long 0x0
5b178 .long 0x2041
5b17c lwz     r0,256(r3)
5b180 .long 0x0
5b184 .long 0xdc
5b188 .long 0xe7333
5b18c rlwnm   r18,r27,r12,29,17
5b190 addic.  r9,r18,13663
5b194 andi.   r5,r19,24932
0005b198 <s3_rgb525_write>:
5b198 stmw    r28,-16(r1)
5b19c mflr    r0
5b1a0 lwz     r31,4(r2)   ; TOC+4 -> D_60480
5b1a4 stw     r0,8(r1)
5b1a8 lwz     r6,0(r31)
5b1ac addi    r29,r3,0
5b1b0 clrlwi  r30,r4,24
5b1b4 stwu    r1,-80(r1)
5b1b8 li      r3,980
5b1bc li      r4,85
5b1c0 lwzu    r11,344(r6)
5b1c4 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x55, r5=?)
5b1c8 lwz     r2,20(r1)
5b1cc lwz     r6,0(r31)
5b1d0 li      r3,981
5b1d4 lwzu    r11,324(r6)
5b1d8 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5b1dc lwz     r2,20(r1)
5b1e0 lwz     r6,0(r31)
5b1e4 clrlwi  r28,r3,24
5b1e8 lwzu    r11,344(r6)
5b1ec ori     r4,r28,1
5b1f0 li      r3,981
5b1f4 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5b1f8 lwz     r2,20(r1)
5b1fc lwz     r6,0(r31)
5b200 clrlwi  r4,r29,24
5b204 lwzu    r11,344(r6)
5b208 li      r3,968
5b20c bl      0x59490   ; SVC out8(r3=0x3c8, r4=?, r5=?)
5b210 lwz     r2,20(r1)
5b214 lwz     r6,0(r31)
5b218 srawi   r7,r29,8
5b21c lwzu    r11,344(r6)
5b220 clrlwi  r4,r7,24
5b224 li      r3,969
5b228 bl      0x59490   ; SVC out8(r3=0x3c9, r4=?, r5=?)
5b22c lwz     r2,20(r1)
5b230 lwz     r6,0(r31)
5b234 addi    r4,r30,0
5b238 lwzu    r11,344(r6)
5b23c li      r3,966
5b240 bl      0x59490   ; SVC out8(r3=0x3c6, r4=?, r5=?)
5b244 lwz     r2,20(r1)
5b248 lwz     r6,0(r31)
5b24c addi    r4,r28,0
5b250 lwzu    r11,344(r6)
5b254 li      r3,981
5b258 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5b25c lwz     r2,20(r1)
5b260 lwz     r12,88(r1)
5b264 addic   r1,r1,80
5b268 mtlr    r12
5b26c lmw     r28,-16(r1)
5b270 blr
5b274 .long 0x0
5b278 .long 0x2041
5b27c lwz     r0,512(r4)
5b280 .long 0x0
5b284 .long 0xdc
5b288 .long 0xf7333
5b28c rlwnm   r18,r27,r12,29,17
5b290 addic.  r9,r18,13663
5b294 andis.  r18,r27,26996
5b298 oris    r0,r8,0
0005b29c <s3_load_palette>:
5b29c mflr    r0
5b2a0 stmw    r25,-28(r1)
5b2a4 lwz     r30,44(r2)   ; TOC+44 -> D_5f014
5b2a8 stw     r0,8(r1)
5b2ac stwu    r1,-96(r1)
5b2b0 addi    r31,r3,0
5b2b4 lwz     r5,3520(r30)
5b2b8 cmpwi   cr1,r31,0
5b2bc cmpwi   r5,0
5b2c0 li      r5,1
5b2c4 li      r3,986
5b2c8 bne     0x5b3a8
5b2cc stw     r5,3520(r30)
5b2d0 lwz     r29,4(r2)   ; TOC+4 -> D_60480
5b2d4 lwz     r28,52(r2)   ; TOC+52 -> D_6049c
5b2d8 bne     cr1,0x5b2e0
5b2dc lwz     r31,56(r2)   ; TOC+56 -> D_5ff24
5b2e0 lwz     r5,0(r29)
5b2e4 lwzu    r11,324(r5)
5b2e8 bl      0x59490   ; SVC in8(r3=0x3da, r4=?, r5=?)
5b2ec lwz     r2,20(r1)
5b2f0 lwz     r5,0(r29)
5b2f4 li      r3,960
5b2f8 lwzu    r11,344(r5)
5b2fc li      r4,0
5b300 bl      0x59490   ; SVC out8(r3=0x3c0, r4=0x0, r5=?)
5b304 lwz     r2,20(r1)
5b308 lwz     r5,0(r29)
5b30c li      r3,968
5b310 lwzu    r11,344(r5)
5b314 li      r4,0
5b318 bl      0x59490   ; SVC out8(r3=0x3c8, r4=0x0, r5=?)
5b31c lwz     r2,20(r1)
5b320 addic   r27,r28,-1
5b324 addic   r26,r31,-1
5b328 li      r25,0
5b32c li      r31,0
5b330 lwz     r28,36(r2)   ; TOC+36 -> D_5f00c
5b334 lbzu    r4,1(r26)
5b338 lbz     r6,0(r28)
5b33c lwz     r5,0(r29)
5b340 cmplwi  r6,3
5b344 cmplwi  cr1,r6,2
5b348 stbu    r4,1(r27)
5b34c lwzu    r11,344(r5)
5b350 li      r3,969
5b354 srwi    r5,r4,2
5b358 beq     0x5b360
5b35c bne     cr1,0x5b364
5b360 addi    r4,r5,0
5b364 bl      0x59490   ; SVC out8(r3=0x3c9, r4=?, r5=?)
5b368 lwz     r2,20(r1)
5b36c addic   r31,r31,1
5b370 cmpwi   r31,768
5b374 blt     0x5b334
5b378 lwz     r5,0(r29)
5b37c li      r3,986
5b380 lwzu    r11,324(r5)
5b384 bl      0x59490   ; SVC in8(r3=0x3da, r4=?, r5=?)
5b388 lwz     r2,20(r1)
5b38c lwz     r5,0(r29)
5b390 li      r3,960
5b394 lwzu    r11,344(r5)
5b398 li      r4,32
5b39c bl      0x59490   ; SVC out8(r3=0x3c0, r4=0x20, r5=?)
5b3a0 lwz     r2,20(r1)
5b3a4 stw     r25,3520(r30)
5b3a8 lwz     r12,104(r1)
5b3ac addic   r1,r1,96
5b3b0 mtlr    r12
5b3b4 lmw     r25,-28(r1)
5b3b8 blr
5b3bc .long 0x0
5b3c0 .long 0x2041
5b3c4 lwz     r0,256(r7)
5b3c8 .long 0x0
5b3cc .long 0x120
5b3d0 .long 0xf7333
5b3d4 rlwnm.  r12,r27,r13,29,16
5b3d8 oris    r31,r2,28769
5b3dc xoris   r5,r3,29812
5b3e0 oris    r0,r8,0
0005b3e4 <s3_video_int_handler>:
5b3e4 stmw    r28,-16(r1)
5b3e8 mflr    r0
5b3ec lwz     r31,4(r2)   ; TOC+4 -> D_60480
5b3f0 stw     r0,8(r1)
5b3f4 lwz     r8,0(r31)
5b3f8 stwu    r1,-80(r1)
5b3fc li      r3,17128
5b400 lwzu    r11,336(r8)
5b404 bl      0x59490   ; SVC in16le(r3=0x42e8, r4=?, r5=?)
5b408 lwz     r2,20(r1)
5b40c mtcrf   1,r3
5b410 lwz     r8,0(r31)
5b414 li      r4,1
5b418 li      r3,17128
5b41c bns     cr7,0x5b5c8
5b420 lwzu    r11,356(r8)
5b424 bl      0x59490   ; SVC out16le(r3=0x42e8, r4=0x1, r5=?)
5b428 lwz     r2,20(r1)
5b42c lwz     r8,0(r31)
5b430 li      r3,980
5b434 lwzu    r11,324(r8)
5b438 bl      0x59490   ; SVC in8(r3=0x3d4, r4=?, r5=?)
5b43c lwz     r2,20(r1)
5b440 lwz     r8,0(r31)
5b444 clrlwi  r30,r3,24
5b448 lwzu    r11,344(r8)
5b44c li      r3,980
5b450 li      r4,17
5b454 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x11, r5=?)
5b458 lwz     r2,20(r1)
5b45c lwz     r8,0(r31)
5b460 li      r3,981
5b464 lwzu    r11,324(r8)
5b468 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5b46c lwz     r2,20(r1)
5b470 lwz     r8,0(r31)
5b474 andi.   r29,r3,239
5b478 lwzu    r11,344(r8)
5b47c li      r3,981
5b480 addi    r4,r29,0
5b484 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5b488 lwz     r2,20(r1)
5b48c lwz     r28,44(r2)   ; TOC+44 -> D_5f014
5b490 li      r8,2
5b494 lwz     r3,3816(r28)
5b498 ori     r9,r29,16
5b49c cmpwi   r3,1
5b4a0 clrlwi  r4,r9,24
5b4a4 li      r3,981
5b4a8 bne     0x5b4c4
5b4ac stw     r8,3816(r28)
5b4b0 lwz     r8,0(r31)
5b4b4 lwzu    r11,344(r8)
5b4b8 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5b4bc lwz     r2,20(r1)
5b4c0 b       0x5b5b0
5b4c4 li      r3,980
5b4c8 li      r4,71
5b4cc lwz     r9,3816(r28)
5b4d0 lwz     r8,0(r31)
5b4d4 cmpwi   r9,2
5b4d8 bne     0x5b5b0
5b4dc lwzu    r11,344(r8)
5b4e0 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x47, r5=?)
5b4e4 lwz     r2,20(r1)
5b4e8 lwz     r3,0(r31)
5b4ec lwz     r8,3820(r28)
5b4f0 lwzu    r11,344(r3)
5b4f4 clrlwi  r4,r8,24
5b4f8 li      r3,981
5b4fc bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5b500 lwz     r2,20(r1)
5b504 lwz     r8,0(r31)
5b508 li      r3,980
5b50c lwzu    r11,344(r8)
5b510 li      r4,70
5b514 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x46, r5=?)
5b518 lwz     r2,20(r1)
5b51c lwz     r8,3820(r28)
5b520 lwz     r3,0(r31)
5b524 srawi   r8,r8,8
5b528 lwzu    r11,344(r3)
5b52c clrlwi  r4,r8,29
5b530 li      r3,981
5b534 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5b538 lwz     r2,20(r1)
5b53c lwz     r8,0(r31)
5b540 li      r3,980
5b544 lwzu    r11,344(r8)
5b548 li      r4,73
5b54c bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x49, r5=?)
5b550 lwz     r2,20(r1)
5b554 lwz     r3,0(r31)
5b558 lwz     r8,3824(r28)
5b55c lwzu    r11,344(r3)
5b560 clrlwi  r4,r8,24
5b564 li      r3,981
5b568 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5b56c lwz     r2,20(r1)
5b570 lwz     r8,0(r31)
5b574 li      r3,980
5b578 lwzu    r11,344(r8)
5b57c li      r4,72
5b580 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x48, r5=?)
5b584 lwz     r2,20(r1)
5b588 lwz     r8,3824(r28)
5b58c lwz     r3,0(r31)
5b590 srawi   r8,r8,8
5b594 lwzu    r11,344(r3)
5b598 clrlwi  r4,r8,24
5b59c li      r3,981
5b5a0 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5b5a4 lwz     r2,20(r1)
5b5a8 li      r3,0
5b5ac stw     r3,3816(r28)
5b5b0 lwz     r3,0(r31)
5b5b4 addi    r4,r30,0
5b5b8 lwzu    r11,344(r3)
5b5bc li      r3,980
5b5c0 bl      0x59490   ; SVC out8(r3=0x3d4, r4=?, r5=?)
5b5c4 lwz     r2,20(r1)
5b5c8 lwz     r12,88(r1)
5b5cc addic   r1,r1,80
5b5d0 mtlr    r12
5b5d4 lmw     r28,-16(r1)
5b5d8 blr
5b5dc .long 0x0
5b5e0 .long 0x2041
5b5e4 lwz     r0,256(r4)
5b5e8 .long 0x0
5b5ec .long 0x1f8
5b5f0 .long 0x147333
5b5f4 rlwnm   r22,r27,r13,5,18
5b5f8 oris    r15,r11,24425
5b5fc xoris   r20,r19,24424
5b600 ori     r14,r11,25708
5b604 oris    r18,r11,0
0005b608 <s3_get_base_address>:
5b608 stmw    r30,-8(r1)
5b60c mflr    r0
5b610 lwz     r31,4(r2)   ; TOC+4 -> D_60480
5b614 stw     r0,8(r1)
5b618 lwz     r5,0(r31)
5b61c stwu    r1,-80(r1)
5b620 li      r3,980
5b624 li      r4,90
5b628 lwzu    r11,344(r5)
5b62c bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x5a, r5=?)
5b630 lwz     r2,20(r1)
5b634 lwz     r4,0(r31)
5b638 li      r3,981
5b63c lwzu    r11,324(r4)
5b640 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5b644 lwz     r2,20(r1)
5b648 lwz     r4,0(r31)
5b64c slwi    r3,r3,16
5b650 oris    r30,r3,49152
5b654 lwzu    r11,344(r4)
5b658 li      r3,980
5b65c li      r4,89
5b660 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x59, r5=?)
5b664 lwz     r2,20(r1)
5b668 lwz     r4,0(r31)
5b66c li      r3,981
5b670 lwzu    r11,324(r4)
5b674 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5b678 lwz     r2,20(r1)
5b67c slwi    r3,r3,24
5b680 or      r3,r30,r3
5b684 lwz     r12,88(r1)
5b688 addic   r1,r1,80
5b68c mtlr    r12
5b690 lmw     r30,-8(r1)
5b694 blr
5b698 .long 0x0
5b69c .long 0x2041
5b6a0 lwz     r0,256(r2)   ; TOC+256 -> D_58f1c
5b6a4 .long 0x0
5b6a8 .long 0x90
5b6ac .long 0x137333
5b6b0 rlwnm   r7,r27,r12,21,26
5b6b4 rlwnm.  r2,r27,r12,5,25
5b6b8 oris    r31,r10,24932
5b6bc oris    r18,r3,25971
5b6c0 andi.   r0,r24,0
0005b6c4 <s3_memory_size>:
5b6c4 mflr    r0
5b6c8 mfcr    r12
5b6cc stmw    r13,-76(r1)
5b6d0 stw     r12,4(r1)
5b6d4 stw     r0,8(r1)
5b6d8 stwu    r1,-144(r1)
5b6dc bl      0x5b608  <s3_get_base_address>   ; call s3_get_base_address(r3=?, r4=?, r5=?, r6=?)
5b6e0 lwz     r20,4(r2)   ; TOC+4 -> D_60480
5b6e4 addi    r29,r3,0
5b6e8 lwz     r4,0(r20)
5b6ec addi    r18,r3,0
5b6f0 lwzu    r11,344(r4)
5b6f4 li      r3,980
5b6f8 li      r4,54
5b6fc bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x36, r5=?)
5b700 lwz     r2,20(r1)
5b704 lwz     r4,0(r20)
5b708 li      r3,981
5b70c lwzu    r11,324(r4)
5b710 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5b714 lwz     r2,20(r1)
5b718 lis     r7,-21846
5b71c addic   r15,r7,21845
5b720 lis     r7,-21930
5b724 addic   r16,r7,-21931
5b728 lis     r4,21930
5b72c lis     r11,21846
5b730 lis     r10,23130
5b734 lis     r9,-21931
5b738 lis     r7,-23130
5b73c clrlwi  r17,r3,24
5b740 addis   r18,r18,64
5b744 addic   r14,r4,23130
5b748 addic   r19,r11,-21846
5b74c addic   r21,r10,23130
5b750 addic   r23,r9,21930
5b754 addic   r25,r7,-23131
5b758 li      r27,4
5b75c addic   r28,r29,4
5b760 addic   r26,r29,8
5b764 addic   r13,r29,12
5b768 li      r22,2
5b76c addic   r24,r4,21930
5b770 lwz     r4,0(r20)
5b774 clrlwi  r7,r17,27
5b778 subfic  r9,r27,4
5b77c cmpwi   cr4,r27,1
5b780 cmpwi   cr1,r27,2
5b784 cmpwi   r27,3
5b788 cmpwi   cr5,r27,4
5b78c rlwimi  r7,r9,6,0,25
5b790 lwzu    r11,344(r4)
5b794 clrlwi  r17,r7,24
5b798 li      r3,980
5b79c li      r4,54
5b7a0 beq     cr4,0x5b7d0
5b7a4 li      r30,2
5b7a8 beq     cr1,0x5b7c8
5b7ac li      r30,3
5b7b0 beq     0x5b7e0
5b7b4 beq     cr5,0x5b7e0
5b7b8 lbz     r30,56(r1)
5b7bc b       0x5b7e8
5b7c0 addi    r3,r27,0
5b7c4 b       0x5b904
5b7c8 stb     r22,56(r1)
5b7cc b       0x5b7e8
5b7d0 li      r7,1
5b7d4 stb     r7,56(r1)
5b7d8 li      r30,1
5b7dc b       0x5b7e8
5b7e0 li      r7,3
5b7e4 stb     r7,56(r1)
5b7e8 bl      0x59490   ; SVC out8(r3=0x4, r4=0x36, r5=?)
5b7ec lwz     r2,20(r1)
5b7f0 lwz     r4,0(r20)
5b7f4 li      r3,981
5b7f8 lwzu    r11,344(r4)
5b7fc addi    r4,r17,0
5b800 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5b804 lwz     r2,20(r1)
5b808 lwz     r4,0(r20)
5b80c li      r3,980
5b810 lwzu    r11,344(r4)
5b814 li      r4,88
5b818 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x58, r5=?)
5b81c lwz     r2,20(r1)
5b820 lwz     r4,0(r20)
5b824 li      r3,981
5b828 addi    r7,r4,0
5b82c lwzu    r31,344(r7)
5b830 lwzu    r11,324(r4)
5b834 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5b838 lwz     r2,20(r1)
5b83c clrrwi  r4,r3,2
5b840 or      r4,r4,r30
5b844 addi    r11,r31,0
5b848 li      r3,981
5b84c bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5b850 lwz     r2,20(r1)
5b854 stw     r24,0(r29)
5b858 stw     r15,0(r28)
5b85c stw     r16,0(r26)
5b860 stw     r19,0(r13)
5b864 lwz     r4,0(r20)
5b868 li      r3,981
5b86c lwzu    r11,324(r4)
5b870 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5b874 lwz     r2,20(r1)
5b878 addis   r18,r18,-16
5b87c addi    r4,r18,0
5b880 bne     cr4,0x5b888
5b884 addic   r4,r4,64
5b888 stw     r21,0(r4)
5b88c stw     r23,4(r4)
5b890 stw     r25,8(r4)
5b894 stw     r14,12(r4)
5b898 lwz     r7,0(r29)
5b89c cmplw   r7,r24
5b8a0 bne     0x5b8f8
5b8a4 lwz     r7,0(r28)
5b8a8 cmplw   cr1,r7,r15
5b8ac bne     cr1,0x5b8f8
5b8b0 lwz     r7,0(r26)
5b8b4 cmplw   r7,r16
5b8b8 bne     0x5b8f8
5b8bc lwz     r7,0(r13)
5b8c0 cmplw   cr1,r7,r19
5b8c4 bne     cr1,0x5b8f8
5b8c8 lwz     r7,0(r4)
5b8cc cmplw   r7,r21
5b8d0 bne     0x5b8f8
5b8d4 lwz     r7,4(r4)
5b8d8 cmplw   cr1,r7,r23
5b8dc bne     cr1,0x5b8f8
5b8e0 lwz     r7,8(r4)
5b8e4 cmplw   r7,r25
5b8e8 bne     0x5b8f8
5b8ec lwz     r4,12(r4)
5b8f0 cmplw   cr1,r4,r14
5b8f4 beq     cr1,0x5b7c0
5b8f8 addic.  r27,r27,-1
5b8fc bgt     0x5b770
5b900 li      r3,0
5b904 lwz     r0,152(r1)
5b908 lwz     r12,148(r1)
5b90c addic   r1,r1,144
5b910 mtcrf   8,r12
5b914 mtlr    r0
5b918 lmw     r13,-76(r1)
5b91c blr
5b920 .long 0x0
5b924 .long 0x2043
5b928 lwz     r0,256(r19)
5b92c .long 0x0
5b930 .long 0x25c
5b934 .long 0xe7333
5b938 rlwnm.  r13,r27,r12,21,22
5b93c xoris   r18,r27,31071
5b940 andi.   r9,r27,31333
0005b944 <s3_init>:
5b944 mflr    r0
5b948 stmw    r25,-28(r1)
5b94c li      r7,255
5b950 lwz     r6,52(r2)   ; TOC+52 -> D_6049c
5b954 li      r29,0
5b958 stw     r0,8(r1)
5b95c stw     r29,768(r6)
5b960 stwu    r1,-96(r1)
5b964 addic   r6,r6,768
5b968 mtctr   r7
5b96c stw     r3,56(r1)
5b970 stw     r4,60(r1)
5b974 li      r28,1
5b978 li      r7,1
5b97c lwz     r8,0(r6)
5b980 addc    r8,r7,r8
5b984 stwu    r8,4(r6)
5b988 addic   r7,r7,1
5b98c bdnz    0x5b980
5b990 bl      0x5bb64  <s3_init_2>   ; call s3_init_2(r3=?, r4=?, r5=?, r6=?)
5b994 lwz     r25,44(r2)   ; TOC+44 -> D_5f014
5b998 addi    r27,r3,0
5b99c lwz     r6,3828(r25)
5b9a0 lwz     r3,56(r1)
5b9a4 cmpwi   r6,0
5b9a8 lwz     r4,60(r1)
5b9ac beq     0x5b9bc
5b9b0 stw     r29,3828(r25)
5b9b4 bl      0x5bb64  <s3_init_2>   ; call s3_init_2(r3=?, r4=?, r5=?, r6=?)
5b9b8 addi    r27,r3,0
5b9bc lbz     r7,3812(r25)
5b9c0 lwz     r6,40(r2)   ; TOC+40 -> D_5f010
5b9c4 cmpwi   cr1,r7,0
5b9c8 lbz     r6,0(r6)
5b9cc cmplwi  r6,2
5b9d0 bne     cr1,0x5ba58
5b9d4 lwz     r31,4(r2)   ; TOC+4 -> D_60480
5b9d8 lwz     r6,0(r31)
5b9dc bne     0x5ba54
5b9e0 lwzu    r11,668(r6)
5b9e4 bl      0x59490   ; SVC svc668(r3=?, r4=?, r5=?)
5b9e8 lwz     r2,20(r1)
5b9ec cmpwi   r3,254
5b9f0 cmpwi   cr7,r3,240
5b9f4 cmpwi   cr1,r3,192
5b9f8 beq     0x5ba1c
5b9fc beq     cr1,0x5ba1c
5ba00 lwz     r6,0(r31)
5ba04 li      r3,2105
5ba08 li      r4,6
5ba0c beq     cr7,0x5ba1c
5ba10 lwzu    r11,344(r6)
5ba14 bl      0x59490   ; SVC out8(r3=0x839, r4=0x6, r5=?)
5ba18 lwz     r2,20(r1)
5ba1c lwz     r6,0(r31)
5ba20 lwz     r5,60(r2)   ; TOC+60 -> D_6032c
5ba24 lwzu    r11,488(r6)
5ba28 li      r3,2
5ba2c li      r4,15
5ba30 bl      0x59490   ; SVC ext_int_registrar(r3=0x2, r4=0xf, r5=?)
5ba34 lwz     r2,20(r1)
5ba38 cmpwi   r3,0
5ba3c crclr   4*cr1+eq
5ba40 lbz     r6,3812(r25)
5ba44 bne     0x5ba50
5ba48 stb     r28,3812(r25)
5ba4c b       0x5ba54
5ba50 cmpwi   cr1,r6,0
5ba54 beq     cr1,0x5bb2c
5ba58 lwz     r30,4(r2)   ; TOC+4 -> D_60480
5ba5c li      r3,980
5ba60 lwz     r6,0(r30)
5ba64 li      r4,17
5ba68 lwzu    r11,344(r6)
5ba6c bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x11, r5=?)
5ba70 lwz     r2,20(r1)
5ba74 lwz     r6,0(r30)
5ba78 li      r3,981
5ba7c lwzu    r11,324(r6)
5ba80 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5ba84 lwz     r2,20(r1)
5ba88 lwz     r6,0(r30)
5ba8c clrlwi  r7,r3,24
5ba90 ori     r31,r7,48
5ba94 lwzu    r11,344(r6)
5ba98 li      r3,981
5ba9c addi    r4,r31,0
5baa0 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5baa4 lwz     r2,20(r1)
5baa8 lwz     r6,0(r30)
5baac li      r3,980
5bab0 lwzu    r11,344(r6)
5bab4 li      r4,50
5bab8 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x32, r5=?)
5babc lwz     r2,20(r1)
5bac0 lwz     r6,0(r30)
5bac4 li      r3,981
5bac8 addi    r7,r6,0
5bacc lwzu    r26,344(r7)
5bad0 lwzu    r11,324(r6)
5bad4 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5bad8 lwz     r2,20(r1)
5badc ori     r4,r3,16
5bae0 addi    r11,r26,0
5bae4 li      r3,981
5bae8 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5baec lwz     r2,20(r1)
5baf0 stw     r29,3824(r25)
5baf4 stw     r29,3820(r25)
5baf8 stw     r28,3816(r25)
5bafc lwz     r6,0(r30)
5bb00 li      r3,980
5bb04 lwzu    r11,344(r6)
5bb08 li      r4,17
5bb0c bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x11, r5=?)
5bb10 lwz     r2,20(r1)
5bb14 lwz     r6,0(r30)
5bb18 andi.   r4,r31,223
5bb1c lwzu    r11,344(r6)
5bb20 li      r3,981
5bb24 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5bb28 lwz     r2,20(r1)
5bb2c addi    r3,r27,0
5bb30 lwz     r12,104(r1)
5bb34 addic   r1,r1,96
5bb38 mtlr    r12
5bb3c lmw     r25,-28(r1)
5bb40 blr
5bb44 .long 0x0
5bb48 .long 0x2041
5bb4c lwz     r0,512(r7)
5bb50 .long 0x0
5bb54 attn
5bb58 .long 0x77333
5bb5c rlwnm.  r9,r27,r13,25,20
5bb60 andis.  r0,r0,0
0005bb64 <s3_init_2>:
5bb64 mflr    r0
5bb68 stmw    r22,-40(r1)
5bb6c cmpwi   r3,513
5bb70 lwz     r23,44(r2)   ; TOC+44 -> D_5f014
5bb74 cmpwi   cr1,r3,517
5bb78 stw     r0,8(r1)
5bb7c addi    r22,r4,0
5bb80 stwu    r1,-112(r1)
5bb84 addic   r4,r23,760
5bb88 beq     0x5bc2c
5bb8c cmpwi   r3,529
5bb90 addic   r4,r23,1528
5bb94 addic   r9,r23,932
5bb98 beq     cr1,0x5bc2c
5bb9c bne     0x5bba8
5bba0 stw     r9,3808(r23)
5bba4 b       0x5bc30
5bba8 lwz     r9,3804(r23)
5bbac cmpwi   cr6,r3,263
5bbb0 cmpwi   r9,2
5bbb4 cmpwi   cr1,r3,628
5bbb8 bge     0x5bbc4
5bbbc li      r3,0
5bbc0 b       0x5c984
5bbc4 cmpwi   r3,279
5bbc8 addic   r4,r23,2660
5bbcc beq     cr6,0x5bc2c
5bbd0 cmpwi   cr6,r3,544
5bbd4 addic   r4,r23,3392
5bbd8 beq     cr1,0x5bc2c
5bbdc cmpwi   cr1,r3,546
5bbe0 addic   r4,r23,1808
5bbe4 beq     0x5bc2c
5bbe8 cmpwi   r9,4
5bbec addic   r4,r23,1104
5bbf0 beq     cr6,0x5bc2c
5bbf4 cmpwi   cr6,r3,538
5bbf8 addic   r4,r23,1980
5bbfc beq     cr1,0x5bc2c
5bc00 cmpwi   cr1,r3,539
5bc04 blt     0x5bbbc
5bc08 cmpwi   r3,629
5bc0c addic   r3,r23,2940
5bc10 bne     cr6,0x5bc1c
5bc14 stw     r3,3808(r23)
5bc18 b       0x5bc30
5bc1c addic   r3,r23,3004
5bc20 addic   r4,r23,3456
5bc24 beq     cr1,0x5bc14
5bc28 bne     0x5bbbc
5bc2c stw     r4,3808(r23)
5bc30 li      r28,1
5bc34 stw     r28,3520(r23)
5bc38 bl      0x5a104  <s3_POS>   ; call s3_POS(r3=?, r4=?, r5=?, r6=?)
5bc3c cmpwi   cr1,r3,0
5bc40 beq     cr1,0x5bbbc
5bc44 lwz     r3,3828(r23)
5bc48 cmpwi   r3,0
5bc4c beq     0x5bc68
5bc50 lwz     r27,40(r2)   ; TOC+40 -> D_5f010
5bc54 lwz     r24,4(r2)   ; TOC+4 -> D_60480
5bc58 li      r3,3
5bc5c stw     r3,3792(r23)
5bc60 li      r25,0
5bc64 b       0x5be50
5bc68 lwz     r27,40(r2)   ; TOC+40 -> D_5f010
5bc6c lbz     r3,0(r27)
5bc70 cmplwi  r3,2
5bc74 bne     0x5bca8
5bc78 lwz     r24,4(r2)   ; TOC+4 -> D_60480
5bc7c lwz     r3,0(r24)
5bc80 lwzu    r11,668(r3)
5bc84 bl      0x59490   ; SVC svc668(r3=?, r4=?, r5=?)
5bc88 lwz     r2,20(r1)
5bc8c cmpwi   r3,254
5bc90 cmpwi   cr1,r22,-1
5bc94 bne     0x5bcac
5bc98 beq     cr1,0x5bc58
5bc9c stw     r22,3792(r23)
5bca0 li      r25,0
5bca4 b       0x5be50
5bca8 lwz     r24,4(r2)   ; TOC+4 -> D_60480
5bcac lwz     r4,0(r24)
5bcb0 li      r3,980
5bcb4 lwzu    r11,344(r4)
5bcb8 li      r4,85
5bcbc bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x55, r5=?)
5bcc0 lwz     r2,20(r1)
5bcc4 lwz     r4,0(r24)
5bcc8 li      r3,981
5bccc lwzu    r11,324(r4)
5bcd0 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5bcd4 lwz     r2,20(r1)
5bcd8 lwz     r9,0(r24)
5bcdc clrlwi  r29,r3,24
5bce0 ori     r4,r29,4
5bce4 lwzu    r11,344(r9)
5bce8 li      r3,981
5bcec bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5bcf0 lwz     r2,20(r1)
5bcf4 lwz     r4,0(r24)
5bcf8 li      r3,968
5bcfc lwzu    r11,324(r4)
5bd00 bl      0x59490   ; SVC in8(r3=0x3c8, r4=?, r5=?)
5bd04 lwz     r2,20(r1)
5bd08 lwz     r4,0(r24)
5bd0c li      r3,972
5bd10 lwzu    r11,324(r4)
5bd14 bl      0x59490   ; SVC in8(r3=0x3cc, r4=?, r5=?)
5bd18 lwz     r2,20(r1)
5bd1c lwz     r4,0(r24)
5bd20 clrlwi  r30,r3,26
5bd24 clrlwi  r26,r3,24
5bd28 lwzu    r11,344(r4)
5bd2c li      r3,962
5bd30 addi    r4,r30,0
5bd34 bl      0x59490   ; SVC out8(r3=0x3c2, r4=?, r5=?)
5bd38 lwz     r2,20(r1)
5bd3c li      r29,15
5bd40 li      r25,0
5bd44 li      r31,0
5bd48 lwz     r4,0(r24)
5bd4c li      r3,968
5bd50 lwzu    r11,324(r4)
5bd54 bl      0x59490   ; SVC in8(r3=0x3c8, r4=?, r5=?)
5bd58 lwz     r2,20(r1)
5bd5c addic   r31,r31,1
5bd60 cmpwi   r31,256
5bd64 clrlwi  r3,r3,28
5bd68 and     r29,r29,r3
5bd6c blt     0x5bd48
5bd70 ori     r3,r30,192
5bd74 lwz     r9,0(r24)
5bd78 clrlwi  r4,r3,24
5bd7c li      r3,962
5bd80 lwzu    r11,344(r9)
5bd84 bl      0x59490   ; SVC out8(r3=0x3c2, r4=?, r5=?)
5bd88 lwz     r2,20(r1)
5bd8c li      r30,0
5bd90 li      r31,0
5bd94 lwz     r4,0(r24)
5bd98 li      r3,968
5bd9c lwzu    r11,324(r4)
5bda0 bl      0x59490   ; SVC in8(r3=0x3c8, r4=?, r5=?)
5bda4 lwz     r2,20(r1)
5bda8 addic   r31,r31,1
5bdac cmpwi   r31,256
5bdb0 clrlwi  r3,r3,28
5bdb4 or      r3,r3,r30
5bdb8 clrlwi  r30,r3,24
5bdbc blt     0x5bd94
5bdc0 xor     r3,r29,r30
5bdc4 cmpwi   cr1,r22,-1
5bdc8 clrlwi  r4,r3,24
5bdcc stw     r29,3800(r23)
5bdd0 stw     r4,3796(r23)
5bdd4 rlwinm  r3,r3,4,20,27
5bdd8 bne     cr1,0x5bdf0
5bddc addc    r3,r29,r3
5bde0 addc    r3,r23,r3
5bde4 lbz     r3,3524(r3)
5bde8 stw     r3,3792(r23)
5bdec b       0x5bdf4
5bdf0 stw     r22,3792(r23)
5bdf4 lwz     r9,0(r24)
5bdf8 addi    r4,r26,0
5bdfc li      r3,962
5be00 lwzu    r11,344(r9)
5be04 bl      0x59490   ; SVC out8(r3=0x3c2, r4=?, r5=?)
5be08 lwz     r2,20(r1)
5be0c lwz     r4,0(r24)
5be10 li      r3,980
5be14 lwzu    r11,344(r4)
5be18 li      r4,85
5be1c bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x55, r5=?)
5be20 lwz     r2,20(r1)
5be24 lwz     r4,0(r24)
5be28 li      r3,981
5be2c lwzu    r11,324(r4)
5be30 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5be34 lwz     r2,20(r1)
5be38 lwz     r9,0(r24)
5be3c andi.   r4,r3,251
5be40 lwzu    r11,344(r9)
5be44 li      r3,981
5be48 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5be4c lwz     r2,20(r1)
5be50 lbz     r3,0(r27)
5be54 cmpwi   r3,0
5be58 bne     0x5bf20
5be5c lwz     r4,0(r24)
5be60 li      r3,980
5be64 lwzu    r11,344(r4)
5be68 li      r4,4
5be6c bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x4, r5=?)
5be70 lwz     r2,20(r1)
5be74 lwz     r4,0(r24)
5be78 li      r3,981
5be7c lwzu    r11,344(r4)
5be80 li      r4,255
5be84 bl      0x59490   ; SVC out8(r3=0x3d5, r4=0xff, r5=?)
5be88 lwz     r2,20(r1)
5be8c lwz     r4,0(r24)
5be90 li      r3,980
5be94 lwzu    r11,344(r4)
5be98 li      r4,93
5be9c bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x5d, r5=?)
5bea0 lwz     r2,20(r1)
5bea4 lwz     r4,0(r24)
5bea8 li      r3,981
5beac addi    r9,r4,0
5beb0 lwzu    r31,344(r9)
5beb4 lwzu    r11,324(r4)
5beb8 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5bebc lwz     r2,20(r1)
5bec0 ori     r4,r3,16
5bec4 addi    r11,r31,0
5bec8 li      r3,981
5becc bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5bed0 lwz     r2,20(r1)
5bed4 lwz     r4,0(r24)
5bed8 li      r3,980
5bedc lwzu    r11,344(r4)
5bee0 li      r4,86
5bee4 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x56, r5=?)
5bee8 lwz     r2,20(r1)
5beec lwz     r4,0(r24)
5bef0 li      r3,981
5bef4 addi    r9,r4,0
5bef8 lwzu    r31,344(r9)
5befc lwzu    r11,324(r4)
5bf00 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5bf04 lwz     r2,20(r1)
5bf08 ori     r4,r3,32
5bf0c addi    r11,r31,0
5bf10 li      r3,981
5bf14 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5bf18 lwz     r2,20(r1)
5bf1c b       0x5bf68
5bf20 lwz     r4,0(r24)
5bf24 li      r3,964
5bf28 lwzu    r11,344(r4)
5bf2c li      r4,13
5bf30 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0xd, r5=?)
5bf34 lwz     r2,20(r1)
5bf38 lwz     r4,0(r24)
5bf3c li      r3,965
5bf40 lwzu    r11,324(r4)
5bf44 bl      0x59490   ; SVC in8(r3=0x3c5, r4=?, r5=?)
5bf48 lwz     r2,20(r1)
5bf4c lwz     r9,0(r24)
5bf50 clrlwi  r3,r3,28
5bf54 ori     r4,r3,80
5bf58 lwzu    r11,344(r9)
5bf5c li      r3,965
5bf60 bl      0x59490   ; SVC out8(r3=0x3c5, r4=?, r5=?)
5bf64 lwz     r2,20(r1)
5bf68 bl      0x5c9b8  <vsync_wait>   ; call vsync_wait(r3=?, r4=?, r5=?, r6=?)
5bf6c lwz     r4,0(r24)
5bf70 li      r3,986
5bf74 lwzu    r11,324(r4)
5bf78 bl      0x59490   ; SVC in8(r3=0x3da, r4=?, r5=?)
5bf7c lwz     r2,20(r1)
5bf80 lwz     r4,0(r24)
5bf84 li      r3,960
5bf88 lwzu    r11,344(r4)
5bf8c li      r4,0
5bf90 bl      0x59490   ; SVC out8(r3=0x3c0, r4=0x0, r5=?)
5bf94 lwz     r2,20(r1)
5bf98 bl      0x5a5a0  <Async_Reset>   ; call Async_Reset(r3=?, r4=?, r5=?, r6=?)
5bf9c lwz     r4,0(r24)
5bfa0 li      r3,964
5bfa4 lwzu    r11,344(r4)
5bfa8 li      r4,2
5bfac bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x2, r5=?)
5bfb0 lwz     r2,20(r1)
5bfb4 lwz     r4,0(r24)
5bfb8 li      r3,965
5bfbc lwzu    r11,344(r4)
5bfc0 li      r4,3
5bfc4 bl      0x59490   ; SVC out8(r3=0x3c5, r4=0x3, r5=?)
5bfc8 lwz     r2,20(r1)
5bfcc lwz     r4,0(r24)
5bfd0 li      r3,964
5bfd4 lwzu    r11,344(r4)
5bfd8 li      r4,3
5bfdc bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x3, r5=?)
5bfe0 lwz     r2,20(r1)
5bfe4 lwz     r4,0(r24)
5bfe8 li      r3,965
5bfec lwzu    r11,344(r4)
5bff0 li      r4,0
5bff4 bl      0x59490   ; SVC out8(r3=0x3c5, r4=0x0, r5=?)
5bff8 lwz     r2,20(r1)
5bffc lwz     r4,0(r24)
5c000 li      r3,964
5c004 lwzu    r11,344(r4)
5c008 li      r4,4
5c00c bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x4, r5=?)
5c010 lwz     r2,20(r1)
5c014 lwz     r4,0(r24)
5c018 li      r3,965
5c01c lwzu    r11,344(r4)
5c020 li      r4,2
5c024 bl      0x59490   ; SVC out8(r3=0x3c5, r4=0x2, r5=?)
5c028 lwz     r2,20(r1)
5c02c addic   r30,r23,110
5c030 li      r31,0
5c034 lwz     r22,36(r2)   ; TOC+36 -> D_5f00c
5c038 lbz     r3,0(r22)
5c03c lbz     r4,0(r30)
5c040 cmplwi  cr1,r3,3
5c044 cmplwi  r4,101
5c048 addic   r9,r30,2
5c04c li      r3,980
5c050 bne     cr1,0x5c060
5c054 bne     0x5c060
5c058 addi    r30,r9,0
5c05c b       0x5c08c
5c060 lwz     r9,0(r24)
5c064 lwzu    r11,344(r9)
5c068 bl      0x59490   ; SVC out8(r3=0x3d4, r4=?, r5=?)
5c06c lwz     r2,20(r1)
5c070 lwz     r3,0(r24)
5c074 lbz     r4,1(r30)
5c078 lwzu    r11,344(r3)
5c07c addic   r30,r30,2
5c080 li      r3,981
5c084 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5c088 lwz     r2,20(r1)
5c08c addic   r31,r31,1
5c090 cmplwi  r31,38
5c094 blt     0x5c038
5c098 lbz     r3,0(r27)
5c09c cmpwi   cr1,r3,0
5c0a0 cmplwi  r3,2
5c0a4 bne     cr1,0x5c10c
5c0a8 lwz     r4,0(r24)
5c0ac li      r3,980
5c0b0 lwzu    r11,344(r4)
5c0b4 li      r4,54
5c0b8 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x36, r5=?)
5c0bc lwz     r2,20(r1)
5c0c0 lwz     r4,0(r24)
5c0c4 li      r3,981
5c0c8 lwzu    r11,344(r4)
5c0cc li      r4,159
5c0d0 bl      0x59490   ; SVC out8(r3=0x3d5, r4=0x9f, r5=?)
5c0d4 lwz     r2,20(r1)
5c0d8 lwz     r4,0(r24)
5c0dc li      r3,980
5c0e0 lwzu    r11,344(r4)
5c0e4 li      r4,55
5c0e8 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x37, r5=?)
5c0ec lwz     r2,20(r1)
5c0f0 lwz     r4,0(r24)
5c0f4 li      r3,981
5c0f8 lwzu    r11,344(r4)
5c0fc li      r4,255
5c100 bl      0x59490   ; SVC out8(r3=0x3d5, r4=0xff, r5=?)
5c104 lwz     r2,20(r1)
5c108 b       0x5c298
5c10c bne     0x5c228
5c110 lbz     r3,0(r22)
5c114 cmplwi  r3,3
5c118 bne     0x5c1c8
5c11c lwz     r4,0(r24)
5c120 li      r3,980
5c124 lwzu    r11,344(r4)
5c128 li      r4,54
5c12c bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x36, r5=?)
5c130 lwz     r2,20(r1)
5c134 lwz     r4,0(r24)
5c138 li      r3,981
5c13c lwzu    r11,324(r4)
5c140 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5c144 lwz     r2,20(r1)
5c148 lwz     r9,0(r24)
5c14c rlwinm  r3,r3,0,28,29
5c150 ori     r4,r3,130
5c154 lwzu    r11,344(r9)
5c158 li      r3,981
5c15c bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5c160 lwz     r2,20(r1)
5c164 lwz     r4,0(r24)
5c168 li      r3,980
5c16c lwzu    r11,344(r4)
5c170 li      r4,55
5c174 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x37, r5=?)
5c178 lwz     r2,20(r1)
5c17c lwz     r4,0(r24)
5c180 li      r3,981
5c184 lwzu    r11,344(r4)
5c188 li      r4,15
5c18c bl      0x59490   ; SVC out8(r3=0x3d5, r4=0xf, r5=?)
5c190 lwz     r2,20(r1)
5c194 lwz     r4,0(r24)
5c198 li      r3,980
5c19c lwzu    r11,344(r4)
5c1a0 li      r4,104
5c1a4 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x68, r5=?)
5c1a8 lwz     r2,20(r1)
5c1ac lwz     r4,0(r24)
5c1b0 li      r3,981
5c1b4 lwzu    r11,344(r4)
5c1b8 li      r4,136
5c1bc bl      0x59490   ; SVC out8(r3=0x3d5, r4=0x88, r5=?)
5c1c0 lwz     r2,20(r1)
5c1c4 b       0x5c228
5c1c8 lwz     r4,0(r24)
5c1cc li      r3,980
5c1d0 lwzu    r11,344(r4)
5c1d4 li      r4,54
5c1d8 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x36, r5=?)
5c1dc lwz     r2,20(r1)
5c1e0 lwz     r4,0(r24)
5c1e4 li      r3,981
5c1e8 lwzu    r11,344(r4)
5c1ec li      r4,142
5c1f0 bl      0x59490   ; SVC out8(r3=0x3d5, r4=0x8e, r5=?)
5c1f4 lwz     r2,20(r1)
5c1f8 lwz     r4,0(r24)
5c1fc li      r3,980
5c200 lwzu    r11,344(r4)
5c204 li      r4,55
5c208 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x37, r5=?)
5c20c lwz     r2,20(r1)
5c210 lwz     r4,0(r24)
5c214 li      r3,981
5c218 lwzu    r11,344(r4)
5c21c li      r4,15
5c220 bl      0x59490   ; SVC out8(r3=0x3d5, r4=0xf, r5=?)
5c224 lwz     r2,20(r1)
5c228 addic   r30,r23,186
5c22c li      r31,0
5c230 lbz     r4,0(r30)
5c234 li      r3,980
5c238 cmplwi  cr1,r4,104
5c23c cmplwi  r4,101
5c240 addic   r9,r30,2
5c244 beq     cr1,0x5c24c
5c248 bne     0x5c260
5c24c lbz     r10,0(r22)
5c250 cmplwi  cr1,r10,3
5c254 bne     cr1,0x5c260
5c258 addi    r30,r9,0
5c25c b       0x5c28c
5c260 lwz     r9,0(r24)
5c264 lwzu    r11,344(r9)
5c268 bl      0x59490   ; SVC out8(r3=0x3d4, r4=?, r5=?)
5c26c lwz     r2,20(r1)
5c270 lwz     r3,0(r24)
5c274 lbz     r4,1(r30)
5c278 lwzu    r11,344(r3)
5c27c addic   r30,r30,2
5c280 li      r3,981
5c284 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5c288 lwz     r2,20(r1)
5c28c addic   r31,r31,1
5c290 cmplwi  r31,15
5c294 blt     0x5c230
5c298 lwz     r3,3808(r23)
5c29c li      r30,1
5c2a0 lwz     r3,4(r3)
5c2a4 addic   r31,r3,19
5c2a8 lwz     r4,0(r24)
5c2ac li      r3,964
5c2b0 lwzu    r11,344(r4)
5c2b4 addi    r4,r30,0
5c2b8 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x1, r5=?)
5c2bc lwz     r2,20(r1)
5c2c0 lwz     r3,0(r24)
5c2c4 lbzu    r4,1(r31)
5c2c8 lwzu    r11,344(r3)
5c2cc li      r3,965
5c2d0 bl      0x59490   ; SVC out8(r3=0x3c5, r4=?, r5=?)
5c2d4 lwz     r2,20(r1)
5c2d8 addic   r30,r30,1
5c2dc cmpwi   r30,4
5c2e0 ble     0x5c2a8
5c2e4 lwz     r4,3808(r23)
5c2e8 lwz     r3,0(r24)
5c2ec lwz     r9,4(r4)
5c2f0 lwz     r4,3792(r23)
5c2f4 lwzu    r11,344(r3)
5c2f8 addc    r4,r9,r4
5c2fc li      r3,962
5c300 lbz     r4,8(r4)
5c304 bl      0x59490   ; SVC out8(r3=0x3c2, r4=?, r5=?)
5c308 lwz     r2,20(r1)
5c30c lwz     r4,0(r24)
5c310 li      r3,964
5c314 lwzu    r11,344(r4)
5c318 li      r4,0
5c31c bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x0, r5=?)
5c320 lwz     r2,20(r1)
5c324 lwz     r4,0(r24)
5c328 li      r3,965
5c32c lwzu    r11,344(r4)
5c330 li      r4,3
5c334 bl      0x59490   ; SVC out8(r3=0x3c5, r4=0x3, r5=?)
5c338 lwz     r2,20(r1)
5c33c lwz     r4,0(r24)
5c340 li      r3,964
5c344 lwzu    r11,344(r4)
5c348 li      r4,9
5c34c bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x9, r5=?)
5c350 lwz     r2,20(r1)
5c354 lwz     r4,0(r24)
5c358 li      r3,965
5c35c lwzu    r11,344(r4)
5c360 li      r4,2
5c364 bl      0x59490   ; SVC out8(r3=0x3c5, r4=0x2, r5=?)
5c368 lwz     r2,20(r1)
5c36c lwz     r4,0(r24)
5c370 li      r3,986
5c374 lwzu    r11,324(r4)
5c378 bl      0x59490   ; SVC in8(r3=0x3da, r4=?, r5=?)
5c37c lwz     r2,20(r1)
5c380 lwz     r3,3808(r23)
5c384 li      r29,0
5c388 lwz     r3,4(r3)
5c38c addic   r30,r3,23
5c390 addic   r26,r3,24
5c394 lwz     r4,0(r24)
5c398 li      r3,960
5c39c lwzu    r11,344(r4)
5c3a0 addi    r4,r29,0
5c3a4 bl      0x59490   ; SVC out8(r3=0x3c0, r4=0x0, r5=?)
5c3a8 lwz     r2,20(r1)
5c3ac lwz     r3,0(r24)
5c3b0 addi    r31,r26,0
5c3b4 lwzu    r11,344(r3)
5c3b8 addic   r26,r26,1
5c3bc lbzu    r4,1(r30)
5c3c0 li      r3,960
5c3c4 bl      0x59490   ; SVC out8(r3=0x3c0, r4=?, r5=?)
5c3c8 lwz     r2,20(r1)
5c3cc addic   r29,r29,1
5c3d0 cmpwi   r29,20
5c3d4 ble     0x5c394
5c3d8 li      r30,0
5c3dc lwz     r4,0(r24)
5c3e0 li      r3,974
5c3e4 lwzu    r11,344(r4)
5c3e8 addi    r4,r30,0
5c3ec bl      0x59490   ; SVC out8(r3=0x3ce, r4=0x0, r5=?)
5c3f0 lwz     r2,20(r1)
5c3f4 lwz     r3,0(r24)
5c3f8 lbzu    r4,1(r31)
5c3fc lwzu    r11,344(r3)
5c400 li      r3,975
5c404 bl      0x59490   ; SVC out8(r3=0x3cf, r4=?, r5=?)
5c408 lwz     r2,20(r1)
5c40c addic   r30,r30,1
5c410 cmpwi   r30,8
5c414 ble     0x5c3dc
5c418 lwz     r4,0(r24)
5c41c li      r3,964
5c420 lwzu    r11,344(r4)
5c424 li      r4,4
5c428 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x4, r5=?)
5c42c lwz     r2,20(r1)
5c430 lwz     r3,0(r24)
5c434 lwz     r4,3808(r23)
5c438 lwzu    r11,344(r3)
5c43c lbz     r4,8(r4)
5c440 li      r3,965
5c444 bl      0x59490   ; SVC out8(r3=0x3c5, r4=?, r5=?)
5c448 lwz     r2,20(r1)
5c44c lwz     r3,3832(r23)
5c450 cmpwi   r3,0
5c454 beq     0x5c498
5c458 lwz     r4,0(r24)
5c45c li      r3,980
5c460 lwzu    r11,344(r4)
5c464 li      r4,102
5c468 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x66, r5=?)
5c46c lwz     r2,20(r1)
5c470 lwz     r3,3808(r23)
5c474 lbz     r9,0(r27)
5c478 lwz     r4,0(r24)
5c47c addc    r3,r9,r3
5c480 lwzu    r11,344(r4)
5c484 lbz     r4,9(r3)
5c488 li      r3,981
5c48c bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5c490 lwz     r2,20(r1)
5c494 b       0x5c4bc
5c498 lwz     r3,3808(r23)
5c49c lbz     r9,0(r27)
5c4a0 lwz     r4,0(r24)
5c4a4 addc    r3,r9,r3
5c4a8 lwzu    r11,356(r4)
5c4ac lbz     r4,9(r3)
5c4b0 li      r3,19176
5c4b4 bl      0x59490   ; SVC out16le(r3=0x4ae8, r4=?, r5=?)
5c4b8 lwz     r2,20(r1)
5c4bc lwz     r9,3808(r23)
5c4c0 lbz     r3,0(r27)
5c4c4 lwz     r4,3792(r23)
5c4c8 slwi    r3,r3,4
5c4cc slwi    r4,r4,2
5c4d0 addc    r3,r3,r4
5c4d4 addc    r3,r9,r3
5c4d8 lwz     r3,16(r3)
5c4dc li      r31,0
5c4e0 lwz     r30,0(r3)
5c4e4 cmpwi   r31,4
5c4e8 li      r3,980
5c4ec addi    r4,r31,0
5c4f0 bne     0x5c510
5c4f4 lbz     r9,0(r27)
5c4f8 lbz     r10,0(r30)
5c4fc cmpwi   cr1,r9,0
5c500 bne     cr1,0x5c510
5c504 stb     r10,56(r1)
5c508 addic   r30,r30,1
5c50c b       0x5c53c
5c510 lwz     r9,0(r24)
5c514 lwzu    r11,344(r9)
5c518 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x0, r5=?)
5c51c lwz     r2,20(r1)
5c520 lwz     r3,0(r24)
5c524 lbz     r4,0(r30)
5c528 lwzu    r11,344(r3)
5c52c addic   r30,r30,1
5c530 li      r3,981
5c534 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5c538 lwz     r2,20(r1)
5c53c addic   r31,r31,1
5c540 cmpwi   cr1,r31,24
5c544 ble     cr1,0x5c4e4
5c548 lwz     r10,3808(r23)
5c54c lbz     r9,0(r27)
5c550 lbz     r4,271(r23)
5c554 lwz     r3,3792(r23)
5c558 cmpwi   r4,0
5c55c slwi    r9,r9,4
5c560 slwi    r3,r3,2
5c564 addc    r3,r9,r3
5c568 addc    r3,r10,r3
5c56c lwz     r3,16(r3)
5c570 addic   r30,r23,271
5c574 lwz     r9,4(r3)
5c578 beq     0x5c5d8
5c57c addic   r31,r9,-1
5c580 lwz     r9,0(r24)
5c584 li      r3,980
5c588 lwzu    r11,344(r9)
5c58c bl      0x59490   ; SVC out8(r3=0x3d4, r4=?, r5=?)
5c590 lwz     r2,20(r1)
5c594 lwz     r3,0(r24)
5c598 lbzu    r4,1(r31)
5c59c lwzu    r11,344(r3)
5c5a0 li      r3,981
5c5a4 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5c5a8 lwz     r2,20(r1)
5c5ac lbzu    r4,1(r30)
5c5b0 cmpwi   r4,0
5c5b4 bne     0x5c580
5c5b8 lbz     r4,0(r27)
5c5bc lwz     r3,3792(r23)
5c5c0 slwi    r9,r4,4
5c5c4 slwi    r4,r3,2
5c5c8 lwz     r3,3808(r23)
5c5cc addc    r4,r9,r4
5c5d0 addc    r3,r3,r4
5c5d4 lwz     r3,16(r3)
5c5d8 lwz     r31,8(r3)
5c5dc lbz     r4,0(r31)
5c5e0 cmpwi   cr1,r4,0
5c5e4 beq     cr1,0x5c644
5c5e8 lbz     r3,0(r22)
5c5ec cmpwi   r4,104
5c5f0 cmplwi  cr1,r3,3
5c5f4 addic   r9,r31,2
5c5f8 li      r3,980
5c5fc bne     cr1,0x5c60c
5c600 bne     0x5c60c
5c604 addi    r31,r9,0
5c608 b       0x5c638
5c60c lwz     r9,0(r24)
5c610 lwzu    r11,344(r9)
5c614 bl      0x59490   ; SVC out8(r3=0x3d4, r4=?, r5=?)
5c618 lwz     r2,20(r1)
5c61c lwz     r3,0(r24)
5c620 lbz     r4,1(r31)
5c624 lwzu    r11,344(r3)
5c628 addic   r31,r31,2
5c62c li      r3,981
5c630 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5c634 lwz     r2,20(r1)
5c638 lbz     r4,0(r31)
5c63c cmpwi   cr1,r4,0
5c640 bne     cr1,0x5c5e8
5c644 lwz     r3,48(r2)   ; TOC+48 -> D_5ff1c
5c648 lbz     r3,0(r3)
5c64c cmplwi  r3,1
5c650 bne     0x5c69c
5c654 lwz     r4,0(r24)
5c658 li      r3,980
5c65c lwzu    r11,344(r4)
5c660 li      r4,88
5c664 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x58, r5=?)
5c668 lwz     r2,20(r1)
5c66c lwz     r4,0(r24)
5c670 li      r3,981
5c674 addi    r9,r4,0
5c678 lwzu    r31,344(r9)
5c67c lwzu    r11,324(r4)
5c680 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5c684 lwz     r2,20(r1)
5c688 ori     r4,r3,64
5c68c addi    r11,r31,0
5c690 li      r3,981
5c694 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5c698 lwz     r2,20(r1)
5c69c lwz     r3,3828(r23)
5c6a0 cmpwi   r3,0
5c6a4 beq     0x5c6b0
5c6a8 li      r3,1
5c6ac b       0x5c984
5c6b0 bl      0x5b6c4  <s3_memory_size>   ; call s3_memory_size(r3=0x1, r4=?, r5=?, r6=?)
5c6b4 lwz     r4,0(r24)
5c6b8 stw     r3,3804(r23)
5c6bc lwzu    r11,344(r4)
5c6c0 li      r3,980
5c6c4 li      r4,54
5c6c8 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x36, r5=?)
5c6cc lwz     r2,20(r1)
5c6d0 lbz     r4,0(r27)
5c6d4 cmplwi  r4,2
5c6d8 bne     0x5c814
5c6dc lwz     r4,0(r24)
5c6e0 li      r3,981
5c6e4 lwzu    r11,324(r4)
5c6e8 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5c6ec lwz     r2,20(r1)
5c6f0 rlwinm  r3,r3,0,24,26
5c6f4 cmplwi  r3,192
5c6f8 bne     0x5c810
5c6fc lwz     r4,0(r24)
5c700 li      r3,980
5c704 lwzu    r11,344(r4)
5c708 li      r4,84
5c70c bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x54, r5=?)
5c710 lwz     r2,20(r1)
5c714 lwz     r4,0(r24)
5c718 li      r3,981
5c71c lwzu    r11,324(r4)
5c720 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5c724 lwz     r2,20(r1)
5c728 lwz     r9,0(r24)
5c72c rlwinm  r4,r3,31,24,28
5c730 lwzu    r11,344(r9)
5c734 li      r3,981
5c738 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5c73c lwz     r2,20(r1)
5c740 lwz     r4,0(r24)
5c744 li      r3,980
5c748 lwzu    r11,344(r4)
5c74c li      r4,97
5c750 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x61, r5=?)
5c754 lwz     r2,20(r1)
5c758 lwz     r4,0(r24)
5c75c li      r3,981
5c760 lwzu    r11,324(r4)
5c764 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5c768 lwz     r2,20(r1)
5c76c lwz     r4,0(r24)
5c770 rlwinm  r31,r3,8,21,23
5c774 lwzu    r11,344(r4)
5c778 li      r3,980
5c77c li      r4,98
5c780 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x62, r5=?)
5c784 lwz     r2,20(r1)
5c788 lwz     r4,0(r24)
5c78c li      r3,981
5c790 lwzu    r11,324(r4)
5c794 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5c798 lwz     r2,20(r1)
5c79c lwz     r4,0(r24)
5c7a0 or      r31,r31,r3
5c7a4 lwzu    r11,344(r4)
5c7a8 rlwinm  r4,r31,1,16,30
5c7ac li      r3,981
5c7b0 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5c7b4 lwz     r2,20(r1)
5c7b8 lwz     r3,0(r24)
5c7bc rlwinm  r31,r31,25,24,31
5c7c0 lwzu    r11,344(r3)
5c7c4 li      r3,980
5c7c8 li      r4,97
5c7cc bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x61, r5=?)
5c7d0 lwz     r2,20(r1)
5c7d4 lwz     r4,0(r24)
5c7d8 li      r3,981
5c7dc addi    r9,r4,0
5c7e0 lwzu    r30,344(r9)
5c7e4 lwzu    r11,324(r4)
5c7e8 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5c7ec lwz     r2,20(r1)
5c7f0 rlwinm  r3,r3,0,24,28
5c7f4 or      r4,r31,r3
5c7f8 addi    r11,r30,0
5c7fc li      r3,981
5c800 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5c804 lwz     r2,20(r1)
5c808 lbz     r4,0(r27)
5c80c b       0x5c814
5c810 lbz     r4,0(r27)
5c814 lwz     r3,3792(r23)
5c818 slwi    r9,r4,4
5c81c slwi    r3,r3,2
5c820 lwz     r4,3808(r23)
5c824 addc    r3,r9,r3
5c828 addc    r3,r4,r3
5c82c lwz     r3,16(r3)
5c830 addic   r3,r3,12
5c834 bl      0x5a6dc  <dac_init>   ; call dac_init(r3=?, r4=?, r5=?, r6=?)
5c838 lbz     r3,0(r27)
5c83c cmpwi   r3,0
5c840 bne     0x5c8c0
5c844 lwz     r4,0(r24)
5c848 li      r3,980
5c84c lwzu    r11,344(r4)
5c850 li      r4,4
5c854 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x4, r5=?)
5c858 lwz     r2,20(r1)
5c85c lwz     r3,0(r24)
5c860 lbz     r4,56(r1)
5c864 lwzu    r11,344(r3)
5c868 li      r3,981
5c86c bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5c870 lwz     r2,20(r1)
5c874 lwz     r4,0(r24)
5c878 li      r3,980
5c87c lwzu    r11,344(r4)
5c880 li      r4,86
5c884 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x56, r5=?)
5c888 lwz     r2,20(r1)
5c88c lwz     r4,0(r24)
5c890 li      r3,981
5c894 addi    r9,r4,0
5c898 lwzu    r31,344(r9)
5c89c lwzu    r11,324(r4)
5c8a0 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5c8a4 lwz     r2,20(r1)
5c8a8 rlwinm  r4,r3,0,27,25
5c8ac addi    r11,r31,0
5c8b0 li      r3,981
5c8b4 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5c8b8 lwz     r2,20(r1)
5c8bc b       0x5c934
5c8c0 lwz     r4,0(r24)
5c8c4 li      r3,964
5c8c8 lwzu    r11,344(r4)
5c8cc li      r4,8
5c8d0 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0x8, r5=?)
5c8d4 lwz     r2,20(r1)
5c8d8 lwz     r4,0(r24)
5c8dc li      r3,965
5c8e0 lwzu    r11,344(r4)
5c8e4 li      r4,6
5c8e8 bl      0x59490   ; SVC out8(r3=0x3c5, r4=0x6, r5=?)
5c8ec lwz     r2,20(r1)
5c8f0 lwz     r4,0(r24)
5c8f4 li      r3,964
5c8f8 lwzu    r11,344(r4)
5c8fc li      r4,13
5c900 bl      0x59490   ; SVC out8(r3=0x3c4, r4=0xd, r5=?)
5c904 lwz     r2,20(r1)
5c908 lwz     r4,0(r24)
5c90c li      r3,965
5c910 lwzu    r11,324(r4)
5c914 bl      0x59490   ; SVC in8(r3=0x3c5, r4=?, r5=?)
5c918 lwz     r2,20(r1)
5c91c lwz     r9,0(r24)
5c920 clrlwi  r4,r3,28
5c924 lwzu    r11,344(r9)
5c928 li      r3,965
5c92c bl      0x59490   ; SVC out8(r3=0x3c5, r4=?, r5=?)
5c930 lwz     r2,20(r1)
5c934 stw     r25,3520(r23)
5c938 li      r3,0
5c93c bl      0x5b29c  <s3_load_palette>   ; call s3_load_palette(r3=0x0, r4=?, r5=?, r6=?)
5c940 li      r3,0
5c944 bl      0x5eec8  <s3_cursor_size>   ; call s3_cursor_size(r3=0x0, r4=?, r5=?, r6=?)
5c948 stw     r28,3520(r23)
5c94c lwz     r4,0(r24)
5c950 li      r3,986
5c954 lwzu    r11,324(r4)
5c958 bl      0x59490   ; SVC in8(r3=0x3da, r4=?, r5=?)
5c95c lwz     r2,20(r1)
5c960 lwz     r4,0(r24)
5c964 li      r3,960
5c968 lwzu    r11,344(r4)
5c96c li      r4,32
5c970 bl      0x59490   ; SVC out8(r3=0x3c0, r4=0x20, r5=?)
5c974 lwz     r2,20(r1)
5c978 stw     r25,3520(r23)
5c97c bl      0x5cda4  <s3_clear_screen>   ; call s3_clear_screen(r3=?, r4=?, r5=?, r6=?)
5c980 li      r3,1
5c984 lwz     r12,120(r1)
5c988 addic   r1,r1,112
5c98c mtlr    r12
5c990 lmw     r22,-40(r1)
5c994 blr
5c998 .long 0x0
5c99c .long 0x2041
5c9a0 lwz     r0,512(r10)
5c9a4 .long 0x0
5c9a8 .long 0xe34
5c9ac .long 0x97333
5c9b0 rlwnm.  r9,r27,r13,25,20
5c9b4 andis.  r31,r2,12800
0005c9b8 <vsync_wait>:
5c9b8 stmw    r28,-16(r1)
5c9bc mflr    r0
5c9c0 lwz     r31,4(r2)   ; TOC+4 -> D_60480
5c9c4 stw     r0,8(r1)
5c9c8 lwz     r6,0(r31)
5c9cc stwu    r1,-96(r1)
5c9d0 li      r3,986
5c9d4 lwzu    r11,324(r6)
5c9d8 bl      0x59490   ; SVC in8(r3=0x3da, r4=?, r5=?)
5c9dc lwz     r2,20(r1)
5c9e0 lwz     r6,0(r31)
5c9e4 clrlwi  r29,r3,24
5c9e8 lis     r8,-15
5c9ec lwzu    r11,404(r6)
5c9f0 addic   r5,r8,-16960
5c9f4 addic   r3,r1,56
5c9f8 li      r4,20
5c9fc bl      0x59490   ; SVC get_timeout_value(r3=?, r4=0x14, r5=0xfff0bdc0)
5ca00 lwz     r2,20(r1)
5ca04 lwz     r6,60(r1)
5ca08 lwz     r8,56(r1)
5ca0c stw     r6,68(r1)
5ca10 lwz     r6,0(r31)
5ca14 lwz     r30,68(r1)
5ca18 addi    r28,r8,0
5ca1c stw     r8,64(r1)
5ca20 lwzu    r11,412(r6)
5ca24 addi    r3,r28,0
5ca28 addi    r4,r30,0
5ca2c bl      0x59490   ; SVC timeout(r3=?, r4=?, r5=?)
5ca30 lwz     r2,20(r1)
5ca34 cmpwi   r3,0
5ca38 mtcrf   1,r29
5ca3c bne     0x5ca84
5ca40 bge     cr7,0x5ca84
5ca44 lwz     r6,0(r31)
5ca48 li      r3,986
5ca4c lwzu    r11,324(r6)
5ca50 bl      0x59490   ; SVC in8(r3=0x3da, r4=?, r5=?)
5ca54 lwz     r2,20(r1)
5ca58 lwz     r6,0(r31)
5ca5c clrlwi  r29,r3,24
5ca60 lwzu    r11,412(r6)
5ca64 addi    r3,r28,0
5ca68 addi    r4,r30,0
5ca6c bl      0x59490   ; SVC timeout(r3=?, r4=?, r5=?)
5ca70 lwz     r2,20(r1)
5ca74 cmpwi   r3,0
5ca78 mtcrf   1,r29
5ca7c bne     0x5ca84
5ca80 blt     cr7,0x5ca44
5ca84 lwz     r6,0(r31)
5ca88 addi    r3,r28,0
5ca8c lwzu    r11,412(r6)
5ca90 addi    r4,r30,0
5ca94 bl      0x59490   ; SVC timeout(r3=?, r4=?, r5=?)
5ca98 lwz     r2,20(r1)
5ca9c cmpwi   r3,0
5caa0 mtcrf   1,r29
5caa4 bne     0x5caec
5caa8 blt     cr7,0x5caec
5caac lwz     r6,0(r31)
5cab0 li      r3,986
5cab4 lwzu    r11,324(r6)
5cab8 bl      0x59490   ; SVC in8(r3=0x3da, r4=?, r5=?)
5cabc lwz     r2,20(r1)
5cac0 lwz     r6,0(r31)
5cac4 clrlwi  r29,r3,24
5cac8 lwzu    r11,412(r6)
5cacc addi    r3,r28,0
5cad0 addi    r4,r30,0
5cad4 bl      0x59490   ; SVC timeout(r3=?, r4=?, r5=?)
5cad8 lwz     r2,20(r1)
5cadc cmpwi   r3,0
5cae0 mtcrf   1,r29
5cae4 bne     0x5caec
5cae8 bge     cr7,0x5caac
5caec lwz     r12,104(r1)
5caf0 addic   r1,r1,96
5caf4 mtlr    r12
5caf8 lmw     r28,-16(r1)
5cafc blr
5cb00 .long 0x0
5cb04 .long 0x2041
5cb08 lwz     r0,256(r4)
5cb0c .long 0x0
5cb10 .long 0x148
5cb14 .long 0xa7673
5cb18 .long 0x796e635f
5cb1c andis.  r1,r27,26996
0005cb20 <fifo_wait>:
5cb20 stmw    r26,-24(r1)
5cb24 mflr    r0
5cb28 lis     r7,1
5cb2c lwz     r31,4(r2)   ; TOC+4 -> D_60480
5cb30 addic   r30,r7,-25880
5cb34 lwz     r7,0(r31)
5cb38 stw     r0,8(r1)
5cb3c addi    r29,r3,0
5cb40 stwu    r1,-112(r1)
5cb44 addi    r3,r30,0
5cb48 lwzu    r11,336(r7)
5cb4c bl      0x59490   ; SVC in16le(r3=0x9ae8, r4=?, r5=?)
5cb50 lwz     r2,20(r1)
5cb54 lwz     r7,0(r31)
5cb58 clrlwi  r28,r3,16
5cb5c lwzu    r11,404(r7)
5cb60 addic   r3,r1,56
5cb64 li      r4,1
5cb68 li      r5,1
5cb6c bl      0x59490   ; SVC get_timeout_value(r3=?, r4=0x1, r5=0x1)
5cb70 lwz     r2,20(r1)
5cb74 lwz     r7,60(r1)
5cb78 lwz     r8,56(r1)
5cb7c stw     r7,68(r1)
5cb80 lwz     r7,0(r31)
5cb84 lwz     r27,68(r1)
5cb88 addi    r26,r8,0
5cb8c stw     r8,64(r1)
5cb90 lwzu    r11,412(r7)
5cb94 addi    r3,r26,0
5cb98 addi    r4,r27,0
5cb9c bl      0x59490   ; SVC timeout(r3=?, r4=?, r5=?)
5cba0 lwz     r2,20(r1)
5cba4 cmpwi   cr1,r3,0
5cba8 li      r7,256
5cbac sraw    r29,r7,r29
5cbb0 and.    r7,r29,r28
5cbb4 bne     cr1,0x5cbfc
5cbb8 beq     0x5cbfc
5cbbc lwz     r7,0(r31)
5cbc0 addi    r3,r30,0
5cbc4 lwzu    r11,336(r7)
5cbc8 bl      0x59490   ; SVC in16le(r3=0x9ae8, r4=?, r5=?)
5cbcc lwz     r2,20(r1)
5cbd0 lwz     r7,0(r31)
5cbd4 clrlwi  r28,r3,16
5cbd8 lwzu    r11,412(r7)
5cbdc addi    r3,r26,0
5cbe0 addi    r4,r27,0
5cbe4 bl      0x59490   ; SVC timeout(r3=?, r4=?, r5=?)
5cbe8 lwz     r2,20(r1)
5cbec cmpwi   cr1,r3,0
5cbf0 and.    r7,r29,r28
5cbf4 bne     cr1,0x5cbfc
5cbf8 bne     0x5cbbc
5cbfc lwz     r7,0(r31)
5cc00 addi    r3,r26,0
5cc04 addi    r4,r27,0
5cc08 lwzu    r11,412(r7)
5cc0c bl      0x59490   ; SVC timeout(r3=?, r4=?, r5=?)
5cc10 lwz     r2,20(r1)
5cc14 cmpwi   cr1,r3,1
5cc18 lwz     r7,0(r31)
5cc1c li      r3,1664
5cc20 li      r4,105
5cc24 bne     cr1,0x5cc34
5cc28 lwzu    r11,344(r7)
5cc2c bl      0x59490   ; SVC out8(r3=0x680, r4=0x69, r5=?)
5cc30 lwz     r2,20(r1)
5cc34 lwz     r12,120(r1)
5cc38 addic   r1,r1,112
5cc3c mtlr    r12
5cc40 lmw     r26,-24(r1)
5cc44 blr
5cc48 .long 0x0
5cc4c .long 0x2041
5cc50 lwz     r0,256(r6)
5cc54 .long 0x0
5cc58 .long 0x128
5cc5c .long 0x96669
5cc60 oris    r15,r19,24439
5cc64 ori     r9,r11,29696
0005cc68 <ge_wait>:
5cc68 stmw    r27,-20(r1)
5cc6c mflr    r0
5cc70 lis     r6,1
5cc74 lwz     r30,4(r2)   ; TOC+4 -> D_60480
5cc78 addic   r31,r6,-25880
5cc7c lwz     r6,0(r30)
5cc80 stw     r0,8(r1)
5cc84 stwu    r1,-112(r1)
5cc88 addi    r3,r31,0
5cc8c lwzu    r11,336(r6)
5cc90 bl      0x59490   ; SVC in16le(r3=0x9ae8, r4=?, r5=?)
5cc94 lwz     r2,20(r1)
5cc98 lwz     r6,0(r30)
5cc9c clrlwi  r29,r3,16
5cca0 lwzu    r11,404(r6)
5cca4 addic   r3,r1,56
5cca8 li      r4,1
5ccac li      r5,1
5ccb0 bl      0x59490   ; SVC get_timeout_value(r3=?, r4=0x1, r5=0x1)
5ccb4 lwz     r2,20(r1)
5ccb8 lwz     r6,60(r1)
5ccbc lwz     r8,56(r1)
5ccc0 stw     r6,68(r1)
5ccc4 lwz     r6,0(r30)
5ccc8 lwz     r27,68(r1)
5cccc addi    r28,r8,0
5ccd0 stw     r8,64(r1)
5ccd4 lwzu    r11,412(r6)
5ccd8 addi    r3,r28,0
5ccdc addi    r4,r27,0
5cce0 bl      0x59490   ; SVC timeout(r3=?, r4=?, r5=?)
5cce4 lwz     r2,20(r1)
5cce8 cmpwi   r3,0
5ccec mtcrf   4,r29
5ccf0 bne     0x5cd38
5ccf4 bne     cr5,0x5cd38
5ccf8 lwz     r6,0(r30)
5ccfc addi    r3,r31,0
5cd00 lwzu    r11,336(r6)
5cd04 bl      0x59490   ; SVC in16le(r3=0x9ae8, r4=?, r5=?)
5cd08 lwz     r2,20(r1)
5cd0c lwz     r6,0(r30)
5cd10 clrlwi  r29,r3,16
5cd14 lwzu    r11,412(r6)
5cd18 addi    r3,r28,0
5cd1c addi    r4,r27,0
5cd20 bl      0x59490   ; SVC timeout(r3=?, r4=?, r5=?)
5cd24 lwz     r2,20(r1)
5cd28 cmpwi   r3,0
5cd2c mtcrf   4,r29
5cd30 bne     0x5cd38
5cd34 beq     cr5,0x5ccf8
5cd38 lwz     r6,0(r30)
5cd3c addi    r3,r28,0
5cd40 addi    r4,r27,0
5cd44 lwzu    r11,412(r6)
5cd48 bl      0x59490   ; SVC timeout(r3=?, r4=?, r5=?)
5cd4c lwz     r2,20(r1)
5cd50 cmpwi   r3,1
5cd54 lwz     r6,0(r30)
5cd58 li      r3,1664
5cd5c li      r4,105
5cd60 bne     0x5cd70
5cd64 lwzu    r11,344(r6)
5cd68 bl      0x59490   ; SVC out8(r3=0x680, r4=0x69, r5=?)
5cd6c lwz     r2,20(r1)
5cd70 lwz     r12,120(r1)
5cd74 addic   r1,r1,112
5cd78 mtlr    r12
5cd7c lmw     r27,-20(r1)
5cd80 blr
5cd84 .long 0x0
5cd88 .long 0x2041
5cd8c lwz     r0,256(r5)
5cd90 .long 0x0
5cd94 .long 0x11c
5cd98 .long 0x76765
5cd9c rlwnm.  r23,r27,r12,5,20
5cda0 andis.  r0,r0,0
0005cda4 <s3_clear_screen>:
5cda4 mflr    r0
5cda8 stmw    r28,-16(r1)
5cdac lwz     r31,44(r2)   ; TOC+44 -> D_5f014
5cdb0 stw     r0,8(r1)
5cdb4 stwu    r1,-80(r1)
5cdb8 li      r3,5
5cdbc li      r6,1
5cdc0 lwz     r5,3520(r31)
5cdc4 cmpwi   r5,0
5cdc8 bne     0x5cef8
5cdcc stw     r6,3520(r31)
5cdd0 bl      0x5cb20  <fifo_wait>   ; call fifo_wait(r3=0x5, r4=?, r5=?, r6=0x1)
5cdd4 lwz     r29,4(r2)   ; TOC+4 -> D_60480
5cdd8 lis     r28,1
5cddc lwz     r5,0(r29)
5cde0 addic   r30,r28,-16664
5cde4 lwzu    r11,356(r5)
5cde8 addi    r3,r30,0
5cdec li      r4,4096
5cdf0 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=0x1000, r5=?)
5cdf4 lwz     r2,20(r1)
5cdf8 lwz     r5,0(r29)
5cdfc addi    r3,r30,0
5ce00 lwzu    r11,356(r5)
5ce04 li      r4,8192
5ce08 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=0x2000, r5=?)
5ce0c lwz     r2,20(r1)
5ce10 lwz     r5,3808(r31)
5ce14 lwz     r6,0(r29)
5ce18 lwz     r5,4(r5)
5ce1c lwzu    r11,356(r6)
5ce20 lha     r5,0(r5)
5ce24 addi    r3,r30,0
5ce28 addic   r5,r5,-1
5ce2c ori     r4,r5,12288
5ce30 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=?, r5=?)
5ce34 lwz     r2,20(r1)
5ce38 lwz     r5,3808(r31)
5ce3c lwz     r6,0(r29)
5ce40 lwz     r5,4(r5)
5ce44 lwzu    r11,356(r6)
5ce48 lha     r5,2(r5)
5ce4c addi    r3,r30,0
5ce50 addic   r5,r5,-1
5ce54 ori     r4,r5,16384
5ce58 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=?, r5=?)
5ce5c lwz     r2,20(r1)
5ce60 lwz     r5,0(r29)
5ce64 addi    r3,r30,0
5ce68 lwzu    r11,356(r5)
5ce6c addic   r4,r28,-8192
5ce70 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=0xe000, r5=?)
5ce74 lwz     r2,20(r1)
5ce78 li      r3,3
5ce7c bl      0x5cb20  <fifo_wait>   ; call fifo_wait(r3=0x3, r4=?, r5=?, r6=?)
5ce80 lwz     r5,0(r29)
5ce84 addic   r3,r28,-21784
5ce88 lwzu    r11,356(r5)
5ce8c addic   r4,r28,-1
5ce90 bl      0x59490   ; SVC out16le(r3=0xaae8, r4=0xffff, r5=?)
5ce94 lwz     r2,20(r1)
5ce98 lwz     r5,0(r29)
5ce9c addic   r3,r28,-20760
5cea0 lwzu    r11,356(r5)
5cea4 li      r4,1
5cea8 bl      0x59490   ; SVC out16le(r3=0xaee8, r4=0x1, r5=?)
5ceac lwz     r2,20(r1)
5ceb0 lwz     r5,0(r29)
5ceb4 addic   r3,r28,-19736
5ceb8 lwzu    r11,356(r5)
5cebc li      r4,0
5cec0 bl      0x59490   ; SVC out16le(r3=0xb2e8, r4=0x0, r5=?)
5cec4 lwz     r2,20(r1)
5cec8 li      r5,0
5cecc stw     r5,3520(r31)
5ced0 lwz     r5,3808(r31)
5ced4 lwz     r7,3784(r31)
5ced8 lwz     r5,4(r5)
5cedc li      r3,0
5cee0 lha     r6,0(r5)
5cee4 lha     r5,2(r5)
5cee8 addic   r6,r6,-1
5ceec addic   r5,r5,-1
5cef0 li      r4,0
5cef4 bl      0x5cf30  <s3_rect_fill>   ; call s3_rect_fill(r3=0x0, r4=0x0, r5=?, r6=?)
5cef8 lwz     r12,88(r1)
5cefc addic   r1,r1,80
5cf00 mtlr    r12
5cf04 lmw     r28,-16(r1)
5cf08 blr
5cf0c .long 0x0
5cf10 .long 0x2041
5cf14 lwz     r0,0(r4)
5cf18 .long 0x168
5cf1c .long 0xf7333
5cf20 rlwnm.  r3,r27,r13,17,18
5cf24 ori     r18,r11,24435
5cf28 ori     r18,r27,25957
5cf2c xoris   r0,r16,0
0005cf30 <s3_rect_fill>:
5cf30 stmw    r24,-32(r1)
5cf34 mflr    r0
5cf38 lwz     r30,44(r2)   ; TOC+44 -> D_5f014
5cf3c stw     r0,8(r1)
5cf40 stwu    r1,-96(r1)
5cf44 addi    r26,r3,0
5cf48 addi    r31,r4,0
5cf4c addi    r28,r5,0
5cf50 addi    r27,r6,0
5cf54 stw     r7,56(r1)
5cf58 li      r3,3
5cf5c lwz     r4,3520(r30)
5cf60 li      r7,1
5cf64 cmpwi   r4,0
5cf68 bne     0x5d058
5cf6c stw     r7,3520(r30)
5cf70 bl      0x5cb20  <fifo_wait>   ; call fifo_wait(r3=0x3, r4=?, r5=?, r6=?)
5cf74 lwz     r25,4(r2)   ; TOC+4 -> D_60480
5cf78 lis     r24,1
5cf7c lwz     r4,0(r25)
5cf80 addic   r3,r24,-17688
5cf84 lwzu    r11,356(r4)
5cf88 li      r4,39
5cf8c bl      0x59490   ; SVC out16le(r3=0xbae8, r4=0x27, r5=?)
5cf90 lwz     r2,20(r1)
5cf94 lwz     r4,0(r25)
5cf98 lwz     r3,56(r1)
5cf9c lwzu    r11,356(r4)
5cfa0 bl      0x5d3a4  <color_xform>   ; call color_xform(r3=?, r4=?, r5=?, r6=?)
5cfa4 addi    r4,r3,0
5cfa8 addic   r3,r24,-22808
5cfac bl      0x59490   ; SVC out16le(r3=0xa6e8, r4=?, r5=?)
5cfb0 lwz     r2,20(r1)
5cfb4 lwz     r4,0(r25)
5cfb8 addic   r29,r24,-16664
5cfbc lwzu    r11,356(r4)
5cfc0 addi    r3,r29,0
5cfc4 addic   r4,r24,-24576
5cfc8 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=0xa000, r5=?)
5cfcc lwz     r2,20(r1)
5cfd0 li      r3,6
5cfd4 bl      0x5cb20  <fifo_wait>   ; call fifo_wait(r3=0x6, r4=?, r5=?, r6=?)
5cfd8 lwz     r4,0(r25)
5cfdc addic   r3,r24,-31000
5cfe0 lwzu    r11,356(r4)
5cfe4 addi    r4,r26,0
5cfe8 bl      0x59490   ; SVC out16le(r3=0x86e8, r4=?, r5=?)
5cfec lwz     r2,20(r1)
5cff0 lwz     r4,0(r25)
5cff4 addic   r3,r24,-32024
5cff8 lwzu    r11,356(r4)
5cffc addi    r4,r31,0
5d000 bl      0x59490   ; SVC out16le(r3=0x82e8, r4=?, r5=?)
5d004 lwz     r2,20(r1)
5d008 lwz     r7,0(r25)
5d00c subfc   r4,r26,r28
5d010 lwzu    r11,356(r7)
5d014 addic   r3,r24,-26904
5d018 bl      0x59490   ; SVC out16le(r3=0x96e8, r4=?, r5=?)
5d01c lwz     r2,20(r1)
5d020 lwz     r7,0(r25)
5d024 subfc   r4,r31,r27
5d028 lwzu    r11,356(r7)
5d02c addi    r3,r29,0
5d030 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=?, r5=?)
5d034 lwz     r2,20(r1)
5d038 lwz     r4,0(r25)
5d03c addic   r3,r24,-25880
5d040 lwzu    r11,356(r4)
5d044 li      r4,16627
5d048 bl      0x59490   ; SVC out16le(r3=0x9ae8, r4=0x40f3, r5=?)
5d04c lwz     r2,20(r1)
5d050 li      r4,0
5d054 stw     r4,3520(r30)
5d058 lwz     r12,104(r1)
5d05c addic   r1,r1,96
5d060 mtlr    r12
5d064 lmw     r24,-32(r1)
5d068 blr
5d06c .long 0x0
5d070 .long 0x2041
5d074 lwz     r0,1280(r8)
5d078 .long 0x0
5d07c .long 0x13c
5d080 .long 0xc7333
5d084 rlwnm.  r18,r27,r12,21,17
5d088 andis.  r31,r2,26217
5d08c xoris   r12,r3,0
0005d090 <s3_scroll_window>:
5d090 stmw    r18,-56(r1)
5d094 mflr    r0
5d098 mfcr    r12
5d09c lwz     r25,44(r2)   ; TOC+44 -> D_5f014
5d0a0 stw     r12,4(r1)
5d0a4 stw     r0,8(r1)
5d0a8 addi    r27,r3,0
5d0ac stwu    r1,-128(r1)
5d0b0 addi    r28,r4,0
5d0b4 addi    r20,r5,0
5d0b8 addi    r21,r6,0
5d0bc addi    r18,r7,0
5d0c0 addi    r22,r8,0
5d0c4 li      r3,2
5d0c8 lwz     r7,3520(r25)
5d0cc li      r8,1
5d0d0 cmpwi   cr1,r7,0
5d0d4 bne     cr1,0x5d360
5d0d8 stw     r8,3520(r25)
5d0dc bl      0x5cb20  <fifo_wait>   ; call fifo_wait(r3=0x2, r4=?, r5=?, r6=?)
5d0e0 lwz     r23,4(r2)   ; TOC+4 -> D_60480
5d0e4 lis     r24,1
5d0e8 lwz     r7,0(r23)
5d0ec addic   r26,r24,-16664
5d0f0 addic   r19,r24,-24576
5d0f4 lwzu    r11,356(r7)
5d0f8 addi    r3,r26,0
5d0fc addi    r4,r19,0
5d100 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=0xa000, r5=?)
5d104 lwz     r2,20(r1)
5d108 lwz     r7,0(r23)
5d10c addic   r30,r24,-17688
5d110 lwzu    r11,356(r7)
5d114 addi    r3,r30,0
5d118 li      r4,103
5d11c bl      0x59490   ; SVC out16le(r3=0xbae8, r4=0x67, r5=?)
5d120 lwz     r2,20(r1)
5d124 subfc.  r29,r18,r20
5d128 subfc   r31,r22,r21
5d12c cmpwi   cr1,r31,0
5d130 li      r3,7
5d134 bne     0x5d13c
5d138 beq     cr1,0x5d1e8
5d13c bl      0x5cb20  <fifo_wait>   ; call fifo_wait(r3=0x7, r4=?, r5=?, r6=?)
5d140 lwz     r7,0(r23)
5d144 addc    r4,r18,r27
5d148 lwzu    r11,356(r7)
5d14c addic   r3,r24,-31000
5d150 bl      0x59490   ; SVC out16le(r3=0x86e8, r4=?, r5=?)
5d154 lwz     r2,20(r1)
5d158 lwz     r7,0(r23)
5d15c addc    r4,r22,r28
5d160 lwzu    r11,356(r7)
5d164 addic   r3,r24,-32024
5d168 bl      0x59490   ; SVC out16le(r3=0x82e8, r4=?, r5=?)
5d16c lwz     r2,20(r1)
5d170 lwz     r7,0(r23)
5d174 addic   r3,r24,-28952
5d178 lwzu    r11,356(r7)
5d17c addi    r4,r27,0
5d180 bl      0x59490   ; SVC out16le(r3=0x8ee8, r4=?, r5=?)
5d184 lwz     r2,20(r1)
5d188 lwz     r7,0(r23)
5d18c addic   r3,r24,-29976
5d190 lwzu    r11,356(r7)
5d194 addi    r4,r28,0
5d198 bl      0x59490   ; SVC out16le(r3=0x8ae8, r4=?, r5=?)
5d19c lwz     r2,20(r1)
5d1a0 lwz     r7,0(r23)
5d1a4 addic   r4,r29,-1
5d1a8 lwzu    r11,356(r7)
5d1ac addic   r3,r24,-26904
5d1b0 bl      0x59490   ; SVC out16le(r3=0x96e8, r4=?, r5=?)
5d1b4 lwz     r2,20(r1)
5d1b8 lwz     r7,0(r23)
5d1bc addic   r4,r31,-1
5d1c0 lwzu    r11,356(r7)
5d1c4 addi    r3,r26,0
5d1c8 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=?, r5=?)
5d1cc lwz     r2,20(r1)
5d1d0 lwz     r7,0(r23)
5d1d4 addic   r3,r24,-25880
5d1d8 lwzu    r11,356(r7)
5d1dc addic   r4,r24,-16205
5d1e0 bl      0x59490   ; SVC out16le(r3=0x9ae8, r4=0xc0b3, r5=?)
5d1e4 lwz     r2,20(r1)
5d1e8 li      r3,3
5d1ec bl      0x5cb20  <fifo_wait>   ; call fifo_wait(r3=0x3, r4=?, r5=?, r6=?)
5d1f0 lwz     r7,0(r23)
5d1f4 addi    r3,r30,0
5d1f8 lwzu    r11,356(r7)
5d1fc li      r4,39
5d200 bl      0x59490   ; SVC out16le(r3=0xbae8, r4=0x27, r5=?)
5d204 lwz     r2,20(r1)
5d208 lwz     r7,0(r23)
5d20c lwz     r3,3784(r25)
5d210 lwzu    r11,356(r7)
5d214 bl      0x5d3a4  <color_xform>   ; call color_xform(r3=?, r4=?, r5=?, r6=?)
5d218 addi    r4,r3,0
5d21c addic   r3,r24,-22808
5d220 bl      0x59490   ; SVC out16le(r3=0xa6e8, r4=?, r5=?)
5d224 lwz     r2,20(r1)
5d228 lwz     r7,0(r23)
5d22c addi    r4,r19,0
5d230 lwzu    r11,356(r7)
5d234 addi    r3,r26,0
5d238 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=0xa000, r5=?)
5d23c lwz     r2,20(r1)
5d240 cmpwi   cr1,r18,0
5d244 cmpwi   cr4,r22,0
5d248 li      r3,5
5d24c li      r30,0
5d250 beq     cr1,0x5d2d4
5d254 bl      0x5cb20  <fifo_wait>   ; call fifo_wait(r3=0x5, r4=?, r5=?, r6=?)
5d258 lwz     r7,0(r23)
5d25c addc    r8,r20,r27
5d260 subfc   r4,r18,r8
5d264 lwzu    r11,356(r7)
5d268 addic   r3,r24,-31000
5d26c bl      0x59490   ; SVC out16le(r3=0x86e8, r4=?, r5=?)
5d270 lwz     r2,20(r1)
5d274 lwz     r7,0(r23)
5d278 addc    r4,r22,r28
5d27c lwzu    r11,356(r7)
5d280 addic   r3,r24,-32024
5d284 bl      0x59490   ; SVC out16le(r3=0x82e8, r4=?, r5=?)
5d288 lwz     r2,20(r1)
5d28c lwz     r7,0(r23)
5d290 addic   r4,r18,-1
5d294 lwzu    r11,356(r7)
5d298 addic   r3,r24,-26904
5d29c bl      0x59490   ; SVC out16le(r3=0x96e8, r4=?, r5=?)
5d2a0 lwz     r2,20(r1)
5d2a4 lwz     r7,0(r23)
5d2a8 addic   r4,r31,-1
5d2ac lwzu    r11,356(r7)
5d2b0 addi    r3,r26,0
5d2b4 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=?, r5=?)
5d2b8 lwz     r2,20(r1)
5d2bc lwz     r7,0(r23)
5d2c0 addic   r3,r24,-25880
5d2c4 lwzu    r11,356(r7)
5d2c8 li      r4,16627
5d2cc bl      0x59490   ; SVC out16le(r3=0x9ae8, r4=0x40f3, r5=?)
5d2d0 lwz     r2,20(r1)
5d2d4 li      r3,5
5d2d8 beq     cr4,0x5d35c
5d2dc bl      0x5cb20  <fifo_wait>   ; call fifo_wait(r3=0x5, r4=?, r5=?, r6=?)
5d2e0 lwz     r7,0(r23)
5d2e4 addc    r4,r18,r27
5d2e8 lwzu    r11,356(r7)
5d2ec addic   r3,r24,-31000
5d2f0 bl      0x59490   ; SVC out16le(r3=0x86e8, r4=?, r5=?)
5d2f4 lwz     r2,20(r1)
5d2f8 lwz     r7,0(r23)
5d2fc addc    r8,r21,r28
5d300 lwzu    r11,356(r7)
5d304 subfc   r4,r22,r8
5d308 addic   r3,r24,-32024
5d30c bl      0x59490   ; SVC out16le(r3=0x82e8, r4=?, r5=?)
5d310 lwz     r2,20(r1)
5d314 lwz     r7,0(r23)
5d318 addi    r4,r29,0
5d31c lwzu    r11,356(r7)
5d320 addic   r3,r24,-26904
5d324 bl      0x59490   ; SVC out16le(r3=0x96e8, r4=?, r5=?)
5d328 lwz     r2,20(r1)
5d32c lwz     r7,0(r23)
5d330 addic   r4,r22,-1
5d334 lwzu    r11,356(r7)
5d338 addi    r3,r26,0
5d33c bl      0x59490   ; SVC out16le(r3=0xbee8, r4=?, r5=?)
5d340 lwz     r2,20(r1)
5d344 lwz     r7,0(r23)
5d348 addic   r3,r24,-25880
5d34c lwzu    r11,356(r7)
5d350 li      r4,16627
5d354 bl      0x59490   ; SVC out16le(r3=0x9ae8, r4=0x40f3, r5=?)
5d358 lwz     r2,20(r1)
5d35c stw     r30,3520(r25)
5d360 lwz     r0,136(r1)
5d364 lwz     r12,132(r1)
5d368 addic   r1,r1,128
5d36c mtcrf   8,r12
5d370 mtlr    r0
5d374 lmw     r18,-56(r1)
5d378 blr
5d37c .long 0x0
5d380 .long 0x2043
5d384 lwz     r0,1536(r14)
5d388 .long 0x0
5d38c .long 0x2ec
5d390 .long 0x107333
5d394 rlwnm   r19,r27,r12,13,25
5d398 xoris   r12,r27,27743
5d39c andis.  r9,r27,28260
5d3a0 xoris   r23,r27,0
0005d3a4 <color_xform>:
5d3a4 lwz     r4,44(r2)   ; TOC+44 -> D_5f014
5d3a8 mulli   r6,r3,3
5d3ac lwz     r4,3808(r4)
5d3b0 lbz     r5,12(r4)
5d3b4 lwz     r4,52(r2)   ; TOC+52 -> D_6049c
5d3b8 cmplwi  r5,8
5d3bc cmplwi  cr1,r5,16
5d3c0 addc    r5,r4,r6
5d3c4 beqlr
5d3c8 lbzx    r4,r4,r6
5d3cc lbz     r3,2(r5)
5d3d0 lbz     r5,1(r5)
5d3d4 rlwinm  r0,r4,8,16,20
5d3d8 slwi    r4,r4,16
5d3dc slwi    r6,r5,8
5d3e0 bne     cr1,0x5d3f4
5d3e4 rlwimi  r0,r5,3,21,26
5d3e8 srwi    r3,r3,3
5d3ec or      r3,r0,r3
5d3f0 blr
5d3f4 or      r4,r4,r6
5d3f8 or      r3,r3,r4
5d3fc blr
5d400 .long 0x0
5d404 .long 0x2040
5d408 .long 0x100
5d40c .long 0x0
5d410 .long 0x5c
5d414 .long 0xb636f
5d418 xoris   r15,r3,29279
5d41c rldcr   r6,r3,r13,61
5d420 xoris   r0,r8,0
0005d424 <s3_putchar>:
5d424 mflr    r0
5d428 stmw    r22,-40(r1)
5d42c lwz     r28,44(r2)   ; TOC+44 -> D_5f014
5d430 stw     r0,8(r1)
5d434 stwu    r1,-112(r1)
5d438 addi    r25,r3,0
5d43c addi    r31,r4,0
5d440 addi    r26,r5,0
5d444 stw     r6,56(r1)
5d448 stw     r7,60(r1)
5d44c addi    r24,r8,0
5d450 lwz     r4,3520(r28)
5d454 li      r3,980
5d458 cmpwi   r4,0
5d45c li      r4,1
5d460 bne     0x5d6a4
5d464 stw     r4,3520(r28)
5d468 lwz     r22,4(r2)   ; TOC+4 -> D_60480
5d46c lwz     r4,0(r22)
5d470 lwzu    r11,324(r4)
5d474 bl      0x59490   ; SVC in8(r3=0x3d4, r4=?, r5=?)
5d478 lwz     r2,20(r1)
5d47c lwz     r4,3788(r28)
5d480 clrlwi  r23,r3,24
5d484 cmpwi   r4,1
5d488 cmpwi   cr6,r4,3
5d48c cmpwi   cr1,r4,2
5d490 li      r4,2
5d494 bne     0x5d4a0
5d498 stw     r4,3788(r28)
5d49c b       0x5d4f8
5d4a0 li      r4,3
5d4a4 li      r9,0
5d4a8 beq     cr1,0x5d498
5d4ac lwz     r8,0(r22)
5d4b0 li      r3,980
5d4b4 li      r4,69
5d4b8 bne     cr6,0x5d4f8
5d4bc stw     r9,3788(r28)
5d4c0 lwzu    r11,344(r8)
5d4c4 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x45, r5=?)
5d4c8 lwz     r2,20(r1)
5d4cc lwz     r4,0(r22)
5d4d0 li      r3,981
5d4d4 lwzu    r11,324(r4)
5d4d8 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5d4dc lwz     r2,20(r1)
5d4e0 lwz     r8,0(r22)
5d4e4 andi.   r4,r3,223
5d4e8 lwzu    r11,344(r8)
5d4ec li      r3,981
5d4f0 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5d4f4 lwz     r2,20(r1)
5d4f8 lwz     r29,0(r24)
5d4fc lwz     r30,4(r24)
5d500 li      r3,5
5d504 bl      0x5cb20  <fifo_wait>   ; call fifo_wait(r3=0x5, r4=?, r5=?, r6=?)
5d508 lwz     r4,0(r22)
5d50c lis     r27,1
5d510 lwzu    r11,356(r4)
5d514 addic   r3,r27,-17688
5d518 li      r4,39
5d51c bl      0x59490   ; SVC out16le(r3=0xbae8, r4=0x27, r5=?)
5d520 lwz     r2,20(r1)
5d524 cmpwi   r31,-1
5d528 lwz     r4,0(r22)
5d52c cmpwi   cr1,r26,-1
5d530 lwzu    r11,356(r4)
5d534 bne     0x5d53c
5d538 lwz     r31,3780(r28)
5d53c addi    r3,r31,0
5d540 bne     cr1,0x5d548
5d544 lwz     r26,3784(r28)
5d548 bl      0x5d3a4  <color_xform>   ; call color_xform(r3=?, r4=?, r5=?, r6=?)
5d54c addi    r4,r3,0
5d550 addic   r3,r27,-22808
5d554 bl      0x59490   ; SVC out16le(r3=0xa6e8, r4=?, r5=?)
5d558 lwz     r2,20(r1)
5d55c lwz     r4,0(r22)
5d560 addic   r3,r27,-18712
5d564 lwzu    r11,356(r4)
5d568 li      r4,7
5d56c bl      0x59490   ; SVC out16le(r3=0xb6e8, r4=0x7, r5=?)
5d570 lwz     r2,20(r1)
5d574 lwz     r4,0(r22)
5d578 addi    r3,r26,0
5d57c lwzu    r11,356(r4)
5d580 bl      0x5d3a4  <color_xform>   ; call color_xform(r3=?, r4=?, r5=?, r6=?)
5d584 addi    r4,r3,0
5d588 addic   r3,r27,-23832
5d58c bl      0x59490   ; SVC out16le(r3=0xa2e8, r4=?, r5=?)
5d590 lwz     r2,20(r1)
5d594 lwz     r4,0(r22)
5d598 addic   r31,r27,-16664
5d59c lwzu    r11,356(r4)
5d5a0 addi    r3,r31,0
5d5a4 addic   r4,r27,-24448
5d5a8 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=0xa080, r5=?)
5d5ac lwz     r2,20(r1)
5d5b0 li      r3,5
5d5b4 bl      0x5cb20  <fifo_wait>   ; call fifo_wait(r3=0x5, r4=?, r5=?, r6=?)
5d5b8 lwz     r8,0(r22)
5d5bc lwz     r4,56(r1)
5d5c0 lwzu    r11,356(r8)
5d5c4 addic   r3,r27,-31000
5d5c8 bl      0x59490   ; SVC out16le(r3=0x86e8, r4=?, r5=?)
5d5cc lwz     r2,20(r1)
5d5d0 lwz     r8,0(r22)
5d5d4 lwz     r4,60(r1)
5d5d8 lwzu    r11,356(r8)
5d5dc addic   r3,r27,-32024
5d5e0 bl      0x59490   ; SVC out16le(r3=0x82e8, r4=?, r5=?)
5d5e4 lwz     r2,20(r1)
5d5e8 lwz     r8,0(r22)
5d5ec addic   r4,r29,-1
5d5f0 lwzu    r11,356(r8)
5d5f4 addic   r3,r27,-26904
5d5f8 bl      0x59490   ; SVC out16le(r3=0x96e8, r4=?, r5=?)
5d5fc lwz     r2,20(r1)
5d600 lwz     r4,0(r22)
5d604 addi    r3,r31,0
5d608 lwzu    r11,356(r4)
5d60c addic   r4,r30,-1
5d610 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=?, r5=?)
5d614 lwz     r2,20(r1)
5d618 bl      0x5cc68  <ge_wait>   ; call ge_wait(r3=?, r4=?, r5=?, r6=?)
5d61c lwz     r4,0(r22)
5d620 addic   r3,r27,-25880
5d624 lwzu    r11,356(r4)
5d628 li      r4,20915
5d62c bl      0x59490   ; SVC out16le(r3=0x9ae8, r4=0x51b3, r5=?)
5d630 lwz     r2,20(r1)
5d634 addic   r4,r29,7
5d638 mullw   r8,r30,r25
5d63c srawi   r4,r4,3
5d640 addze   r4,r4
5d644 mullw.  r31,r30,r4
5d648 lwz     r4,8(r24)
5d64c addic   r31,r31,-1
5d650 addc    r4,r8,r4
5d654 addic   r30,r4,-1
5d658 beq     0x5d684
5d65c addic   r29,r27,-7448
5d660 lwz     r8,0(r22)
5d664 lbzu    r4,1(r30)
5d668 lwzu    r11,356(r8)
5d66c addi    r3,r29,0
5d670 bl      0x59490   ; SVC out16le(r3=0xe2e8, r4=?, r5=?)
5d674 lwz     r2,20(r1)
5d678 cmpwi   r31,0
5d67c addic   r31,r31,-1
5d680 bne     0x5d660
5d684 lwz     r8,0(r22)
5d688 addi    r4,r23,0
5d68c lwzu    r11,344(r8)
5d690 li      r3,980
5d694 bl      0x59490   ; SVC out8(r3=0x3d4, r4=?, r5=?)
5d698 lwz     r2,20(r1)
5d69c li      r4,0
5d6a0 stw     r4,3520(r28)
5d6a4 lwz     r12,120(r1)
5d6a8 addic   r1,r1,112
5d6ac mtlr    r12
5d6b0 lmw     r22,-40(r1)
5d6b4 blr
5d6b8 .long 0x0
5d6bc .long 0x2041
5d6c0 lwz     r0,1536(r10)
5d6c4 .long 0x0
5d6c8 .long 0x294
5d6cc .long 0xa7333
5d6d0 rlwnm   r16,r27,r14,21,26
5d6d4 ori     r8,r27,24946
0005d6d8 <nearest>:
5d6d8 stmw    r18,-56(r1)
5d6dc mflr    r0
5d6e0 lwz     r7,52(r2)   ; TOC+52 -> D_6049c
5d6e4 srawi   r8,r3,16
5d6e8 addic   r25,r7,768
5d6ec srawi   r7,r3,8
5d6f0 clrlwi  r19,r7,24
5d6f4 lis     r7,-32768
5d6f8 addic   r24,r7,-1
5d6fc stw     r0,8(r1)
5d700 li      r20,0
5d704 lis     r7,21845
5d708 stwu    r1,-128(r1)
5d70c addi    r27,r4,0
5d710 clrlwi  r18,r3,24
5d714 clrlwi  r28,r8,24
5d718 addic   r21,r7,21846
5d71c addi    r22,r20,0
5d720 lwz     r23,4(r2)   ; TOC+4 -> D_60480
5d724 lbzx    r7,r27,r22
5d728 addic   r8,r22,1
5d72c subfc   r3,r28,r7
5d730 mulhw   r9,r21,r22
5d734 addic   r7,r22,2
5d738 lbzx    r29,r27,r7
5d73c lwz     r7,0(r23)
5d740 lbzx    r26,r27,r8
5d744 srwi    r8,r9,31
5d748 addic   r22,r22,3
5d74c addc    r30,r9,r8
5d750 lwzu    r11,24(r7)
5d754 bl      0x59490   ; SVC abs(r3=?, r4=?, r5=?)
5d758 lwz     r2,20(r1)
5d75c lwz     r7,0(r23)
5d760 slwi    r8,r3,2
5d764 lwzx    r31,r25,r8
5d768 lwzu    r11,24(r7)
5d76c subfc   r3,r19,r26
5d770 bl      0x59490   ; SVC abs(r3=?, r4=?, r5=?)
5d774 lwz     r2,20(r1)
5d778 lwz     r7,0(r23)
5d77c slwi    r8,r3,2
5d780 lwzx    r26,r25,r8
5d784 lwzu    r11,24(r7)
5d788 subfc   r3,r18,r29
5d78c bl      0x59490   ; SVC abs(r3=?, r4=?, r5=?)
5d790 lwz     r2,20(r1)
5d794 slwi    r7,r3,2
5d798 lwzx    r7,r25,r7
5d79c addc    r8,r31,r26
5d7a0 addc    r7,r8,r7
5d7a4 cmpw    cr1,r7,r24
5d7a8 cmpwi   r22,768
5d7ac bge     cr1,0x5d7b8
5d7b0 addi    r24,r7,0
5d7b4 addi    r20,r30,0
5d7b8 blt     0x5d724
5d7bc clrlwi  r3,r20,24
5d7c0 lwz     r12,136(r1)
5d7c4 addic   r1,r1,128
5d7c8 mtlr    r12
5d7cc lmw     r18,-56(r1)
5d7d0 blr
5d7d4 .long 0x0
5d7d8 .long 0x2041
5d7dc lwz     r0,512(r14)
5d7e0 .long 0x0
5d7e4 .long 0xfc
5d7e8 .long 0x76e65
5d7ec ori     r18,r11,25971
5d7f0 andis.  r0,r0,0
0005d7f4 <compute_pad>:
5d7f4 mfcr    r12
5d7f8 cmpwi   cr1,r4,4
5d7fc cmpwi   cr6,r4,24
5d800 cmpwi   r4,8
5d804 cmpwi   cr4,r4,16
5d808 stw     r12,4(r1)
5d80c beq     cr1,0x5d834
5d810 cmpwi   cr1,r5,4
5d814 cmpwi   cr7,r5,8
5d818 cmpwi   cr5,r5,24
5d81c beq     0x5d83c
5d820 mcrf    cr7,cr1
5d824 cmpwi   cr1,r5,8
5d828 beq     cr4,0x5d870
5d82c beq     cr6,0x5d870
5d830 b       0x5d880
5d834 addi    r0,r3,0
5d838 b       0x5d880
5d83c beq     cr1,0x5d858
5d840 addic   r4,r3,1
5d844 srawi   r4,r4,1
5d848 addze   r4,r4
5d84c beq     cr7,0x5d868
5d850 beq     cr5,0x5d87c
5d854 b       0x5d880
5d858 addic   r3,r3,1
5d85c srawi   r0,r3,1
5d860 addze   r0,r0
5d864 b       0x5d880
5d868 slwi    r0,r4,1
5d86c b       0x5d880
5d870 beq     cr7,0x5d858
5d874 beq     cr1,0x5d834
5d878 b       0x5d850
5d87c mulli   r0,r3,3
5d880 srawi   r3,r0,2
5d884 addze   r3,r3
5d888 slwi    r3,r3,2
5d88c subfc.  r3,r3,r0
5d890 cmpwi   cr6,r3,3
5d894 cmpwi   cr1,r3,1
5d898 cmpwi   cr7,r3,2
5d89c beq     0x5d8b0
5d8a0 beq     cr1,0x5d8b8
5d8a4 beq     cr7,0x5d8c0
5d8a8 beq     cr6,0x5d8c8
5d8ac b       0x5d8cc
5d8b0 li      r6,0
5d8b4 b       0x5d8cc
5d8b8 li      r6,3
5d8bc b       0x5d8cc
5d8c0 li      r6,2
5d8c4 b       0x5d8cc
5d8c8 li      r6,1
5d8cc addi    r3,r6,0
5d8d0 lwz     r12,4(r1)
5d8d4 mtcrf   8,r12
5d8d8 blr
5d8dc .long 0x0
5d8e0 .long 0x2042
5d8e4 .long 0x300
5d8e8 .long 0x0
5d8ec .long 0xe8
5d8f0 .long 0xb636f
5d8f4 xoris   r16,r11,30068
5d8f8 oris    r31,r10,28769
5d8fc oris    r0,r0,0
0005d900 <s3_getbitmap>:
5d900 stmw    r21,-44(r1)
5d904 mflr    r0
5d908 lwz     r26,44(r2)   ; TOC+44 -> D_5f014
5d90c stw     r0,8(r1)
5d910 stwu    r1,-112(r1)
5d914 addi    r23,r3,0
5d918 addi    r27,r4,0
5d91c addi    r24,r6,0
5d920 lwz     r7,3520(r26)
5d924 subfc   r8,r23,r5
5d928 cmpwi   r7,0
5d92c addic   r22,r8,1
5d930 li      r7,1
5d934 li      r21,0
5d938 bne     0x5da8c
5d93c stw     r7,3520(r26)
5d940 lwz     r7,3808(r26)
5d944 srawi   r8,r22,2
5d948 addze   r8,r8
5d94c lbz     r7,12(r7)
5d950 lwz     r25,4(r2)   ; TOC+4 -> D_60480
5d954 cmplwi  cr1,r7,8
5d958 slwi    r8,r8,2
5d95c lwz     r7,0(r25)
5d960 bne     cr1,0x5da80
5d964 subfc.  r8,r8,r22
5d968 lwzu    r11,156(r7)
5d96c cmpwi   cr7,r8,3
5d970 cmpwi   cr1,r8,1
5d974 subfc   r7,r27,r24
5d978 cmpwi   cr6,r8,2
5d97c addic   r31,r7,1
5d980 beq     0x5da78
5d984 beq     cr1,0x5da70
5d988 beq     cr6,0x5da68
5d98c bne     cr7,0x5d994
5d990 li      r0,1
5d994 addc    r28,r22,r0
5d998 mullw   r0,r28,r31
5d99c addic   r3,r0,276
5d9a0 bl      0x59490   ; SVC malloc(r3=?, r4=?, r5=?)
5d9a4 lwz     r2,20(r1)
5d9a8 cmpwi   cr1,r3,0
5d9ac addi    r30,r3,0
5d9b0 bne     cr1,0x5d9bc
5d9b4 li      r3,0
5d9b8 b       0x5da8c
5d9bc addic   r0,r3,20
5d9c0 sth     r31,2(r30)
5d9c4 stw     r0,12(r30)
5d9c8 li      r0,256
5d9cc sth     r0,4(r30)
5d9d0 mtctr   r0
5d9d4 li      r0,8
5d9d8 sth     r0,6(r30)
5d9dc sth     r22,0(r30)
5d9e0 addic   r31,r3,276
5d9e4 sth     r21,8(r30)
5d9e8 stb     r21,16(r30)
5d9ec li      r0,0
5d9f0 addic   r7,r3,19
5d9f4 stbu    r0,1(r7)
5d9f8 addic   r0,r0,1
5d9fc bdnz    0x5d9f4
5da00 bl      0x5b608  <s3_get_base_address>   ; call s3_get_base_address(r3=0x0, r4=?, r5=?, r6=?)
5da04 lwz     r7,3808(r26)
5da08 cmpw    cr1,r24,r27
5da0c lwz     r7,4(r7)
5da10 addi    r29,r3,0
5da14 lha     r0,2(r7)
5da18 mullw   r0,r0,r24
5da1c addc    r0,r23,r0
5da20 addc    r29,r0,r29
5da24 blt     cr1,0x5da84
5da28 lwz     r7,0(r25)
5da2c addi    r3,r31,0
5da30 lwzu    r11,172(r7)
5da34 addi    r4,r29,0
5da38 addi    r5,r22,0
5da3c bl      0x59490   ; SVC memcpy(r3=0x114, r4=?, r5=?)
5da40 lwz     r2,20(r1)
5da44 lwz     r7,3808(r26)
5da48 addic   r24,r24,-1
5da4c lwz     r7,4(r7)
5da50 cmpw    cr1,r24,r27
5da54 lha     r0,2(r7)
5da58 addc    r31,r28,r31
5da5c subfc   r29,r0,r29
5da60 bge     cr1,0x5da28
5da64 b       0x5da84
5da68 li      r0,2
5da6c b       0x5d994
5da70 li      r0,3
5da74 b       0x5d994
5da78 li      r0,0
5da7c b       0x5d994
5da80 li      r30,0
5da84 stw     r21,3520(r26)
5da88 addi    r3,r30,0
5da8c lwz     r12,120(r1)
5da90 addic   r1,r1,112
5da94 mtlr    r12
5da98 lmw     r21,-44(r1)
5da9c blr
5daa0 .long 0x0
5daa4 .long 0x2041
5daa8 lwz     r0,1024(r11)
5daac .long 0x0
5dab0 .long 0x1a0
5dab4 .long 0xc7333
5dab8 rlwnm   r7,r27,r12,21,26
5dabc ori     r9,r19,29805
5dac0 ori     r16,r11,0
0005dac4 <s3_putbitmap>:
5dac4 mflr    r0
5dac8 stmw    r20,-48(r1)
5dacc stw     r0,8(r1)
5dad0 lwz     r20,44(r2)   ; TOC+44 -> D_5f014
5dad4 stwu    r1,-128(r1)
5dad8 addi    r28,r3,0
5dadc stw     r4,60(r1)
5dae0 stw     r5,64(r1)
5dae4 lwz     r5,3520(r20)
5dae8 li      r7,1
5daec cmpwi   r5,0
5daf0 bne     0x5e1d4
5daf4 stw     r7,3520(r20)
5daf8 lha     r7,2(r28)
5dafc lha     r5,0(r28)
5db00 clrlwi  r29,r7,16
5db04 clrlwi  r24,r5,16
5db08 li      r3,3
5db0c bl      0x5cb20  <fifo_wait>   ; call fifo_wait(r3=0x3, r4=?, r5=?, r6=?)
5db10 lwz     r22,4(r2)   ; TOC+4 -> D_60480
5db14 lis     r23,1
5db18 lwz     r5,0(r22)
5db1c addic   r3,r23,-17688
5db20 lwzu    r11,356(r5)
5db24 li      r4,71
5db28 bl      0x59490   ; SVC out16le(r3=0xbae8, r4=0x47, r5=?)
5db2c lwz     r2,20(r1)
5db30 lwz     r5,0(r22)
5db34 addic   r21,r23,-16664
5db38 lwzu    r11,356(r5)
5db3c addi    r3,r21,0
5db40 addic   r4,r23,-24576
5db44 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=0xa000, r5=?)
5db48 lwz     r2,20(r1)
5db4c lha     r5,8(r28)
5db50 cmpwi   r5,0
5db54 beq     0x5db74
5db58 lwz     r5,0(r22)
5db5c addi    r3,r21,0
5db60 lwzu    r11,356(r5)
5db64 addic   r4,r23,-7936
5db68 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=0xe100, r5=?)
5db6c lwz     r2,20(r1)
5db70 b       0x5db8c
5db74 lwz     r5,0(r22)
5db78 addi    r3,r21,0
5db7c lwzu    r11,356(r5)
5db80 addic   r4,r23,-8192
5db84 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=0xe000, r5=?)
5db88 lwz     r2,20(r1)
5db8c li      r3,6
5db90 bl      0x5cb20  <fifo_wait>   ; call fifo_wait(r3=0x6, r4=?, r5=?, r6=?)
5db94 lwz     r5,0(r22)
5db98 lwz     r4,60(r1)
5db9c lwzu    r11,356(r5)
5dba0 addic   r3,r23,-31000
5dba4 bl      0x59490   ; SVC out16le(r3=0x86e8, r4=?, r5=?)
5dba8 lwz     r2,20(r1)
5dbac lwz     r5,0(r22)
5dbb0 lwz     r4,64(r1)
5dbb4 lwzu    r11,356(r5)
5dbb8 addic   r3,r23,-32024
5dbbc bl      0x59490   ; SVC out16le(r3=0x82e8, r4=?, r5=?)
5dbc0 lwz     r2,20(r1)
5dbc4 lwz     r5,0(r22)
5dbc8 addic   r4,r24,-1
5dbcc lwzu    r11,356(r5)
5dbd0 addic   r3,r23,-26904
5dbd4 bl      0x59490   ; SVC out16le(r3=0x96e8, r4=?, r5=?)
5dbd8 lwz     r2,20(r1)
5dbdc lwz     r5,0(r22)
5dbe0 addic   r30,r29,-1
5dbe4 lwzu    r11,356(r5)
5dbe8 addi    r3,r21,0
5dbec addi    r4,r30,0
5dbf0 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=?, r5=?)
5dbf4 lwz     r2,20(r1)
5dbf8 bl      0x5cc68  <ge_wait>   ; call ge_wait(r3=?, r4=?, r5=?, r6=?)
5dbfc lwz     r5,0(r22)
5dc00 addic   r3,r23,-25880
5dc04 lwzu    r11,356(r5)
5dc08 li      r4,17201
5dc0c bl      0x59490   ; SVC out16le(r3=0x9ae8, r4=0x4331, r5=?)
5dc10 lwz     r2,20(r1)
5dc14 lwz     r25,12(r28)
5dc18 lwz     r5,3808(r20)
5dc1c lha     r7,4(r28)
5dc20 addi    r31,r25,0
5dc24 lbz     r4,12(r5)
5dc28 addc    r25,r25,r7
5dc2c lha     r5,6(r28)
5dc30 addi    r3,r24,0
5dc34 bl      0x5d7f4  <compute_pad>   ; call compute_pad(r3=?, r4=?, r5=?, r6=?)
5dc38 lwz     r5,3808(r20)
5dc3c addi    r26,r3,0
5dc40 lbz     r5,12(r5)
5dc44 cmpwi   cr1,r5,4
5dc48 cmpwi   r5,24
5dc4c cmpwi   cr7,r5,8
5dc50 cmpwi   cr6,r5,16
5dc54 beq     cr1,0x5e1ac
5dc58 beq     cr7,0x5df50
5dc5c beq     cr6,0x5ddb8
5dc60 bne     0x5e1ac
5dc64 lha     r5,6(r28)
5dc68 cmpwi   r5,4
5dc6c cmpwi   cr1,r5,24
5dc70 cmpwi   cr7,r5,8
5dc74 beq     0x5dd0c
5dc78 beq     cr7,0x5dc84
5dc7c beq     cr1,0x5e140
5dc80 b       0x5e1ac
5dc84 cmpwi   r29,0
5dc88 clrlwi  r30,r30,16
5dc8c addic   r31,r23,-7448
5dc90 beq     0x5e1ac
5dc94 lwz     r29,52(r2)   ; TOC+52 -> D_6049c
5dc98 addi    r27,r24,0
5dc9c cmpwi   r27,0
5dca0 addic   r28,r27,-1
5dca4 beq     0x5dcf4
5dca8 lbz     r7,0(r25)
5dcac lbz     r5,1(r25)
5dcb0 lbzx    r7,r29,r7
5dcb4 lbzx    r5,r29,r5
5dcb8 slwi    r4,r7,16
5dcbc slwi    r5,r5,8
5dcc0 or      r7,r4,r5
5dcc4 lbz     r5,2(r25)
5dcc8 addic   r25,r25,3
5dccc lbzx    r9,r29,r5
5dcd0 lwz     r5,0(r22)
5dcd4 or      r4,r7,r9
5dcd8 lwzu    r11,352(r5)
5dcdc addi    r3,r31,0
5dce0 bl      0x59490   ; SVC out32(r3=0xe2e8, r4=?, r5=?)
5dce4 lwz     r2,20(r1)
5dce8 cmpwi   r28,0
5dcec addic   r28,r28,-1
5dcf0 bne     0x5dca8
5dcf4 cmplwi  cr7,r30,0
5dcf8 addic   r5,r30,-1
5dcfc addc    r25,r25,r26
5dd00 clrlwi  r30,r5,16
5dd04 bne     cr7,0x5dc9c
5dd08 b       0x5e1ac
5dd0c cmpwi   r29,0
5dd10 clrlwi  r29,r30,16
5dd14 addic   r30,r23,-7448
5dd18 beq     0x5e1ac
5dd1c lwz     r28,52(r2)   ; TOC+52 -> D_6049c
5dd20 addi    r27,r24,0
5dd24 cmpwi   r27,0
5dd28 addic   r31,r25,-1
5dd2c beq     0x5dda0
5dd30 mtcrf   1,r27
5dd34 lwz     r5,0(r22)
5dd38 lbzu    r7,1(r31)
5dd3c lwzu    r11,352(r5)
5dd40 addic   r25,r25,1
5dd44 addic   r27,r27,-1
5dd48 addi    r3,r30,0
5dd4c addic   r9,r7,1
5dd50 addic   r5,r7,2
5dd54 bns     cr7,0x5dd68
5dd58 srwi    r7,r7,4
5dd5c srwi    r9,r9,4
5dd60 srwi    r5,r5,4
5dd64 b       0x5dd74
5dd68 clrlwi  r7,r7,28
5dd6c clrlwi  r9,r9,28
5dd70 clrlwi  r5,r5,28
5dd74 lbzx    r7,r28,r7
5dd78 lbzx    r9,r28,r9
5dd7c lbzx    r5,r28,r5
5dd80 slwi    r7,r7,16
5dd84 slwi    r9,r9,8
5dd88 or      r7,r7,r9
5dd8c or      r4,r7,r5
5dd90 bl      0x59490   ; SVC out32(r3=0xe2e8, r4=?, r5=?)
5dd94 lwz     r2,20(r1)
5dd98 cmpwi   r27,0
5dd9c bne     0x5dd30
5dda0 cmplwi  cr7,r29,0
5dda4 addic   r5,r29,-1
5dda8 addc    r25,r25,r26
5ddac clrlwi  r29,r5,16
5ddb0 bne     cr7,0x5dd20
5ddb4 b       0x5e1ac
5ddb8 lha     r5,6(r28)
5ddbc cmpwi   cr7,r5,4
5ddc0 cmpwi   r5,24
5ddc4 cmpwi   cr1,r5,8
5ddc8 beq     cr7,0x5dec0
5ddcc beq     cr1,0x5de54
5ddd0 bne     0x5e1ac
5ddd4 cmpwi   r29,0
5ddd8 clrlwi  r29,r30,16
5dddc addic   r30,r23,-7448
5dde0 beq     0x5e1ac
5dde4 cmpwi   r24,0
5dde8 addic   r31,r24,-1
5ddec beq     0x5de3c
5ddf0 lbz     r7,0(r25)
5ddf4 lbz     r5,1(r25)
5ddf8 srwi    r4,r7,3
5ddfc rlwinm  r5,r5,3,21,26
5de00 or      r5,r4,r5
5de04 clrlwi  r7,r5,16
5de08 lbz     r5,2(r25)
5de0c addic   r25,r25,3
5de10 rlwinm  r5,r5,8,16,20
5de14 or      r5,r7,r5
5de18 clrlwi  r4,r5,16
5de1c lwz     r5,0(r22)
5de20 addi    r3,r30,0
5de24 lwzu    r11,348(r5)
5de28 bl      0x59490   ; SVC out16(r3=0xe2e8, r4=?, r5=?)
5de2c lwz     r2,20(r1)
5de30 cmpwi   r31,0
5de34 addic   r31,r31,-1
5de38 bne     0x5ddf0
5de3c cmplwi  cr7,r29,0
5de40 addic   r5,r29,-1
5de44 addc    r25,r25,r26
5de48 clrlwi  r29,r5,16
5de4c bne     cr7,0x5dde4
5de50 b       0x5e1ac
5de54 cmpwi   r29,0
5de58 clrlwi  r27,r30,16
5de5c addic   r29,r23,-7448
5de60 beq     0x5e1ac
5de64 cmpwi   r24,0
5de68 addic   r30,r24,-1
5de6c addic   r28,r25,-1
5de70 beq     0x5dea8
5de74 lbzu    r5,1(r28)
5de78 addic   r25,r25,1
5de7c lbzx    r3,r5,r31
5de80 bl      0x5d3a4  <color_xform>   ; call color_xform(r3=?, r4=?, r5=?, r6=?)
5de84 lwz     r5,0(r22)
5de88 clrlwi  r4,r3,16
5de8c lwzu    r11,348(r5)
5de90 addi    r3,r29,0
5de94 bl      0x59490   ; SVC out16(r3=0xe2e8, r4=?, r5=?)
5de98 lwz     r2,20(r1)
5de9c cmpwi   r30,0
5dea0 addic   r30,r30,-1
5dea4 bne     0x5de74
5dea8 cmplwi  cr7,r27,0
5deac addic   r5,r27,-1
5deb0 addc    r25,r25,r26
5deb4 clrlwi  r27,r5,16
5deb8 bne     cr7,0x5de64
5debc b       0x5e1ac
5dec0 cmpwi   r29,0
5dec4 clrlwi  r28,r30,16
5dec8 addic   r30,r23,-7448
5decc beq     0x5e1ac
5ded0 addi    r27,r24,0
5ded4 cmpwi   r27,0
5ded8 addic   r29,r25,-1
5dedc beq     0x5df38
5dee0 mtcrf   1,r27
5dee4 addic   r27,r27,-1
5dee8 lbz     r5,1(r29)
5deec bns     cr7,0x5df04
5def0 srwi    r5,r5,4
5def4 lbzx    r3,r5,r31
5def8 bl      0x5d3a4  <color_xform>   ; call color_xform(r3=?, r4=?, r5=?, r6=?)
5defc clrlwi  r4,r3,16
5df00 b       0x5df1c
5df04 lbzu    r5,1(r29)
5df08 addic   r25,r25,1
5df0c clrlwi  r5,r5,28
5df10 lbzx    r3,r31,r5
5df14 bl      0x5d3a4  <color_xform>   ; call color_xform(r3=?, r4=?, r5=?, r6=?)
5df18 clrlwi  r4,r3,16
5df1c lwz     r5,0(r22)
5df20 addi    r3,r30,0
5df24 lwzu    r11,348(r5)
5df28 bl      0x59490   ; SVC out16(r3=0xe2e8, r4=?, r5=?)
5df2c lwz     r2,20(r1)
5df30 cmpwi   r27,0
5df34 bne     0x5dee0
5df38 cmplwi  cr7,r28,0
5df3c addic   r5,r28,-1
5df40 addc    r25,r25,r26
5df44 clrlwi  r28,r5,16
5df48 bne     cr7,0x5ded0
5df4c b       0x5e1ac
5df50 lha     r5,6(r28)
5df54 cmpwi   cr7,r5,4
5df58 cmpwi   r5,24
5df5c cmpwi   cr1,r5,8
5df60 beq     cr7,0x5e0c0
5df64 beq     cr1,0x5e044
5df68 bne     0x5e1ac
5df6c cmpwi   r29,0
5df70 clrlwi  r28,r30,16
5df74 beq     0x5e1ac
5df78 addic   r29,r23,-7448
5df7c lwz     r27,52(r2)   ; TOC+52 -> D_6049c
5df80 cmpwi   cr7,r24,0
5df84 li      r31,1
5df88 addic   r30,r24,-1
5df8c beq     cr7,0x5e00c
5df90 lbz     r5,1(r25)
5df94 lbz     r9,0(r25)
5df98 lbz     r7,2(r25)
5df9c cmpwi   r31,0
5dfa0 slwi    r5,r5,8
5dfa4 rlwimi  r5,r9,16,0,15
5dfa8 or      r3,r7,r5
5dfac addic   r25,r25,3
5dfb0 beq     0x5dfcc
5dfb4 li      r31,0
5dfb8 addi    r4,r27,0
5dfbc bl      0x5d6d8  <nearest>   ; call nearest(r3=?, r4=?, r5=?, r6=?)
5dfc0 clrlwi  r5,r3,24
5dfc4 sth     r5,56(r1)
5dfc8 b       0x5e000
5dfcc li      r31,1
5dfd0 addi    r4,r27,0
5dfd4 bl      0x5d6d8  <nearest>   ; call nearest(r3=?, r4=?, r5=?, r6=?)
5dfd8 lhz     r9,56(r1)
5dfdc rlwinm  r7,r3,8,16,23
5dfe0 lwz     r5,0(r22)
5dfe4 or      r7,r9,r7
5dfe8 sth     r7,56(r1)
5dfec clrlwi  r4,r7,16
5dff0 lwzu    r11,348(r5)
5dff4 addi    r3,r29,0
5dff8 bl      0x59490   ; SVC out16(r3=0xe2e8, r4=?, r5=?)
5dffc lwz     r2,20(r1)
5e000 cmpwi   r30,0
5e004 addic   r30,r30,-1
5e008 bne     0x5df90
5e00c cmpwi   r31,0
5e010 addc    r25,r25,r26
5e014 lhz     r4,56(r1)
5e018 addi    r3,r29,0
5e01c bne     0x5e030
5e020 lwz     r5,0(r22)
5e024 lwzu    r11,348(r5)
5e028 bl      0x59490   ; SVC out16(r3=0xe2e8, r4=?, r5=?)
5e02c lwz     r2,20(r1)
5e030 cmplwi  r28,0
5e034 addic   r5,r28,-1
5e038 clrlwi  r28,r5,16
5e03c bne     0x5df80
5e040 b       0x5e1ac
5e044 cmpwi   r29,0
5e048 addic   r5,r24,1
5e04c clrlwi  r28,r30,16
5e050 srwi    r27,r5,1
5e054 beq     0x5e1ac
5e058 addic   r30,r23,-7448
5e05c cmpwi   r27,0
5e060 addic   r29,r27,-1
5e064 beq     0x5e0a8
5e068 lbz     r5,1(r25)
5e06c lbz     r7,0(r25)
5e070 lbzx    r5,r5,r31
5e074 lbzx    r7,r7,r31
5e078 slwi    r5,r5,8
5e07c or      r5,r7,r5
5e080 clrlwi  r4,r5,16
5e084 lwz     r5,0(r22)
5e088 addic   r25,r25,2
5e08c addi    r3,r30,0
5e090 lwzu    r11,348(r5)
5e094 bl      0x59490   ; SVC out16(r3=0xe2e8, r4=?, r5=?)
5e098 lwz     r2,20(r1)
5e09c cmpwi   r29,0
5e0a0 addic   r29,r29,-1
5e0a4 bne     0x5e068
5e0a8 cmplwi  cr7,r28,0
5e0ac addic   r5,r28,-1
5e0b0 addc    r25,r25,r26
5e0b4 clrlwi  r28,r5,16
5e0b8 bne     cr7,0x5e05c
5e0bc b       0x5e1ac
5e0c0 cmpwi   r29,0
5e0c4 addic   r5,r24,1
5e0c8 clrlwi  r24,r30,16
5e0cc srwi    r28,r5,1
5e0d0 beq     0x5e1ac
5e0d4 addic   r30,r23,-7448
5e0d8 cmpwi   r28,0
5e0dc addic   r29,r28,-1
5e0e0 addic   r27,r25,-1
5e0e4 beq     0x5e128
5e0e8 lbzu    r9,1(r27)
5e0ec lwz     r5,0(r22)
5e0f0 clrlwi  r7,r9,28
5e0f4 lwzu    r11,348(r5)
5e0f8 lbzx    r7,r31,r7
5e0fc srwi    r5,r9,4
5e100 lbzx    r5,r31,r5
5e104 slwi    r7,r7,8
5e108 addic   r25,r25,1
5e10c addi    r3,r30,0
5e110 or      r4,r7,r5
5e114 bl      0x59490   ; SVC out16(r3=0xe2e8, r4=?, r5=?)
5e118 lwz     r2,20(r1)
5e11c cmpwi   r29,0
5e120 addic   r29,r29,-1
5e124 bne     0x5e0e8
5e128 cmplwi  cr7,r24,0
5e12c addic   r5,r24,-1
5e130 addc    r25,r25,r26
5e134 clrlwi  r24,r5,16
5e138 bne     cr7,0x5e0d8
5e13c b       0x5e1ac
5e140 cmpwi   r29,0
5e144 clrlwi  r29,r30,16
5e148 addic   r30,r23,-7448
5e14c beq     0x5e1ac
5e150 cmpwi   r24,0
5e154 addic   r31,r24,-1
5e158 beq     0x5e198
5e15c lbz     r5,1(r25)
5e160 lbz     r7,0(r25)
5e164 slwi    r5,r5,8
5e168 or      r5,r5,r7
5e16c lbz     r7,2(r25)
5e170 addic   r25,r25,3
5e174 or      r4,r7,r5
5e178 lwz     r5,0(r22)
5e17c addi    r3,r30,0
5e180 lwzu    r11,352(r5)
5e184 bl      0x59490   ; SVC out32(r3=0xe2e8, r4=?, r5=?)
5e188 lwz     r2,20(r1)
5e18c cmpwi   r31,0
5e190 addic   r31,r31,-1
5e194 bne     0x5e15c
5e198 cmplwi  cr7,r29,0
5e19c addic   r5,r29,-1
5e1a0 addc    r25,r25,r26
5e1a4 clrlwi  r29,r5,16
5e1a8 bne     cr7,0x5e150
5e1ac li      r3,1
5e1b0 bl      0x5cb20  <fifo_wait>   ; call fifo_wait(r3=0x1, r4=?, r5=?, r6=?)
5e1b4 lwz     r5,0(r22)
5e1b8 addi    r3,r21,0
5e1bc lwzu    r11,356(r5)
5e1c0 addic   r4,r23,-8192
5e1c4 bl      0x59490   ; SVC out16le(r3=0xbee8, r4=0xe000, r5=?)
5e1c8 lwz     r2,20(r1)
5e1cc li      r5,0
5e1d0 stw     r5,3520(r20)
5e1d4 lwz     r12,136(r1)
5e1d8 addic   r1,r1,128
5e1dc mtlr    r12
5e1e0 lmw     r20,-48(r1)
5e1e4 blr
5e1e8 .long 0x0
5e1ec .long 0x2041
5e1f0 lwz     r0,768(r12)
5e1f4 .long 0x0
5e1f8 .long 0x724
5e1fc .long 0xc7333
5e200 rlwnm   r16,r27,r14,21,26
5e204 ori     r9,r19,29805
5e208 ori     r16,r11,0
0005e20c <bt485_goto_xy>:
5e20c stmw    r28,-16(r1)
5e210 mflr    r0
5e214 lwz     r29,4(r2)   ; TOC+4 -> D_60480
5e218 stw     r0,8(r1)
5e21c lwz     r6,0(r29)
5e220 addi    r30,r4,0
5e224 stwu    r1,-80(r1)
5e228 addi    r31,r5,0
5e22c li      r3,980
5e230 li      r4,69
5e234 lwzu    r11,344(r6)
5e238 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x45, r5=?)
5e23c lwz     r2,20(r1)
5e240 lwz     r6,0(r29)
5e244 li      r3,981
5e248 lwzu    r11,324(r6)
5e24c bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5e250 lwz     r2,20(r1)
5e254 lwz     r6,0(r29)
5e258 ori     r4,r3,32
5e25c lwzu    r11,344(r6)
5e260 li      r3,981
5e264 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5e268 lwz     r2,20(r1)
5e26c lwz     r6,0(r29)
5e270 li      r3,980
5e274 lwzu    r11,344(r6)
5e278 li      r4,85
5e27c bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x55, r5=?)
5e280 lwz     r2,20(r1)
5e284 lwz     r6,0(r29)
5e288 li      r3,981
5e28c lwzu    r11,324(r6)
5e290 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5e294 lwz     r2,20(r1)
5e298 lwz     r6,0(r29)
5e29c ori     r4,r3,3
5e2a0 lwzu    r11,344(r6)
5e2a4 li      r3,981
5e2a8 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5e2ac lwz     r2,20(r1)
5e2b0 lwz     r28,44(r2)   ; TOC+44 -> D_5f014
5e2b4 lwz     r3,0(r29)
5e2b8 lwz     r7,3808(r28)
5e2bc lwzu    r11,344(r3)
5e2c0 lbz     r3,12(r7)
5e2c4 li      r9,0
5e2c8 cmplwi  r3,8
5e2cc li      r3,968
5e2d0 lwz     r8,3792(r28)
5e2d4 addi    r6,r9,0
5e2d8 bne     0x5e2ec
5e2dc lwz     r6,4(r7)
5e2e0 addc    r7,r6,r8
5e2e4 lbz     r6,16(r7)
5e2e8 lbz     r9,12(r7)
5e2ec addic   r7,r9,32
5e2f0 addic   r6,r6,32
5e2f4 addc    r30,r7,r30
5e2f8 addc    r31,r6,r31
5e2fc clrlwi  r4,r30,24
5e300 bl      0x59490   ; SVC out8(r3=0x3c8, r4=?, r5=?)
5e304 lwz     r2,20(r1)
5e308 lwz     r3,0(r29)
5e30c srawi   r6,r30,8
5e310 lwzu    r11,344(r3)
5e314 clrlwi  r4,r6,24
5e318 li      r3,969
5e31c bl      0x59490   ; SVC out8(r3=0x3c9, r4=?, r5=?)
5e320 lwz     r2,20(r1)
5e324 lwz     r3,0(r29)
5e328 clrlwi  r4,r31,24
5e32c lwzu    r11,344(r3)
5e330 li      r3,966
5e334 bl      0x59490   ; SVC out8(r3=0x3c6, r4=?, r5=?)
5e338 lwz     r2,20(r1)
5e33c lwz     r3,0(r29)
5e340 srawi   r6,r31,8
5e344 lwzu    r11,344(r3)
5e348 clrlwi  r4,r6,24
5e34c li      r3,967
5e350 bl      0x59490   ; SVC out8(r3=0x3c7, r4=?, r5=?)
5e354 lwz     r2,20(r1)
5e358 lwz     r6,0(r29)
5e35c li      r3,980
5e360 lwzu    r11,344(r6)
5e364 li      r4,85
5e368 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x55, r5=?)
5e36c lwz     r2,20(r1)
5e370 lwz     r6,0(r29)
5e374 li      r3,981
5e378 lwzu    r11,324(r6)
5e37c bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5e380 lwz     r2,20(r1)
5e384 lwz     r6,0(r29)
5e388 clrrwi  r4,r3,2
5e38c lwzu    r11,344(r6)
5e390 li      r3,981
5e394 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5e398 lwz     r2,20(r1)
5e39c li      r3,1
5e3a0 stw     r3,3788(r28)
5e3a4 lwz     r12,88(r1)
5e3a8 addic   r1,r1,80
5e3ac mtlr    r12
5e3b0 lmw     r28,-16(r1)
5e3b4 blr
5e3b8 .long 0x0
5e3bc .long 0x2041
5e3c0 lwz     r0,768(r4)
5e3c4 .long 0x0
5e3c8 .long 0x1ac
5e3cc .long 0xd6274
5e3d0 addic.  r1,r24,13663
5e3d4 oris    r15,r27,29807
5e3d8 rlwnm   r24,r27,r15,4,0
0005e3dc <rgb525_goto_xy>:
5e3dc stmw    r30,-8(r1)
5e3e0 mflr    r0
5e3e4 addi    r31,r4,0
5e3e8 stw     r0,8(r1)
5e3ec stwu    r1,-80(r1)
5e3f0 addi    r30,r5,0
5e3f4 clrlwi  r4,r31,24
5e3f8 li      r3,49
5e3fc bl      0x5b198  <s3_rgb525_write>   ; call s3_rgb525_write(r3=0x31, r4=?, r5=?, r6=?)
5e400 srawi   r0,r31,8
5e404 clrlwi  r4,r0,28
5e408 li      r3,50
5e40c bl      0x5b198  <s3_rgb525_write>   ; call s3_rgb525_write(r3=0x32, r4=?, r5=?, r6=?)
5e410 clrlwi  r4,r30,24
5e414 li      r3,51
5e418 bl      0x5b198  <s3_rgb525_write>   ; call s3_rgb525_write(r3=0x33, r4=?, r5=?, r6=?)
5e41c srawi   r0,r30,8
5e420 clrlwi  r4,r0,28
5e424 li      r3,52
5e428 bl      0x5b198  <s3_rgb525_write>   ; call s3_rgb525_write(r3=0x34, r4=?, r5=?, r6=?)
5e42c lwz     r12,88(r1)
5e430 addic   r1,r1,80
5e434 mtlr    r12
5e438 lmw     r30,-8(r1)
5e43c blr
5e440 .long 0x0
5e444 .long 0x2041
5e448 lwz     r0,768(r2)   ; TOC+768 -> D_58f1c
5e44c .long 0x0
5e450 .long 0x64
5e454 .long 0xe7267
5e458 ori     r21,r17,12853
5e45c rlwnm   r7,r27,r13,29,26
5e460 xoris   r31,r26,30841
0005e464 <s3dac_goto_xy>:
5e464 stmw    r27,-20(r1)
5e468 mflr    r0
5e46c lwz     r28,44(r2)   ; TOC+44 -> D_5f014
5e470 lwz     r31,4(r2)   ; TOC+4 -> D_60480
5e474 lbz     r7,3812(r28)
5e478 stw     r0,8(r1)
5e47c cmpwi   r7,0
5e480 addi    r29,r4,0
5e484 addi    r30,r5,0
5e488 stwu    r1,-96(r1)
5e48c li      r3,980
5e490 lwz     r5,0(r31)
5e494 li      r4,17
5e498 beq     0x5e538
5e49c lwzu    r11,344(r5)
5e4a0 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x11, r5=?)
5e4a4 lwz     r2,20(r1)
5e4a8 lwz     r5,0(r31)
5e4ac li      r3,981
5e4b0 addi    r7,r5,0
5e4b4 lwzu    r27,344(r7)
5e4b8 lwzu    r11,324(r5)
5e4bc bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5e4c0 lwz     r2,20(r1)
5e4c4 andi.   r4,r3,239
5e4c8 addi    r11,r27,0
5e4cc li      r3,981
5e4d0 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5e4d4 lwz     r2,20(r1)
5e4d8 li      r5,0
5e4dc stw     r5,3816(r28)
5e4e0 stw     r29,3820(r28)
5e4e4 li      r5,1
5e4e8 stw     r30,3824(r28)
5e4ec stw     r5,3816(r28)
5e4f0 lwz     r5,0(r31)
5e4f4 li      r3,980
5e4f8 lwzu    r11,344(r5)
5e4fc li      r4,17
5e500 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x11, r5=?)
5e504 lwz     r2,20(r1)
5e508 lwz     r5,0(r31)
5e50c li      r3,981
5e510 addi    r7,r5,0
5e514 lwzu    r31,344(r7)
5e518 lwzu    r11,324(r5)
5e51c bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5e520 lwz     r2,20(r1)
5e524 ori     r4,r3,16
5e528 addi    r11,r31,0
5e52c li      r3,981
5e530 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5e534 lwz     r2,20(r1)
5e538 lwz     r12,104(r1)
5e53c addic   r1,r1,96
5e540 mtlr    r12
5e544 lmw     r27,-20(r1)
5e548 blr
5e54c .long 0x0
5e550 .long 0x2041
5e554 lwz     r0,768(r5)
5e558 .long 0x0
5e55c .long 0xe8
5e560 .long 0xd7333
5e564 oris    r1,r3,25439
5e568 oris    r15,r27,29807
5e56c rlwnm   r24,r27,r15,4,0
0005e570 <s3_goto_xy>:
5e570 mflr    r0
5e574 stw     r31,-4(r1)
5e578 lwz     r31,44(r2)   ; TOC+44 -> D_5f014
5e57c stw     r0,8(r1)
5e580 stwu    r1,-80(r1)
5e584 li      r7,1
5e588 lwz     r6,3520(r31)
5e58c cmpwi   r6,0
5e590 bne     0x5e5cc
5e594 stw     r7,3520(r31)
5e598 lwz     r6,36(r2)   ; TOC+36 -> D_5f00c
5e59c lbz     r6,0(r6)
5e5a0 cmpwi   cr1,r6,0
5e5a4 cmplwi  r6,1
5e5a8 bne     cr1,0x5e5b4
5e5ac bl      0x5e20c  <bt485_goto_xy>   ; call bt485_goto_xy(r3=?, r4=?, r5=?, r6=?)
5e5b0 b       0x5e5c4
5e5b4 bne     0x5e5c0
5e5b8 bl      0x5e3dc  <rgb525_goto_xy>   ; call rgb525_goto_xy(r3=?, r4=?, r5=?, r6=?)
5e5bc b       0x5e5c4
5e5c0 bl      0x5e464  <s3dac_goto_xy>   ; call s3dac_goto_xy(r3=?, r4=?, r5=?, r6=?)
5e5c4 li      r3,0
5e5c8 stw     r3,3520(r31)
5e5cc lwz     r12,88(r1)
5e5d0 lwz     r31,76(r1)
5e5d4 mtlr    r12
5e5d8 addic   r1,r1,80
5e5dc blr
5e5e0 .long 0x0
5e5e4 .long 0x2041
5e5e8 lwz     r0,768(r1)
5e5ec .long 0x0
5e5f0 .long 0x70
5e5f4 .long 0xa7333
5e5f8 rlwnm   r7,r27,r13,29,26
5e5fc xoris   r31,r26,30841
0005e600 <s3_set_colors>:
5e600 cmpwi   r3,-1
5e604 cmpwi   cr1,r4,-1
5e608 lwz     r5,44(r2)   ; TOC+44 -> D_5f014
5e60c beq     0x5e614
5e610 stw     r3,3780(r5)
5e614 addi    r3,r5,0
5e618 beqlr   cr1
5e61c stw     r4,3784(r3)
5e620 blr
5e624 .long 0x0
5e628 .long 0x2040
5e62c attn
5e630 .long 0x0
5e634 .long 0x24
5e638 .long 0xd7333
5e63c rlwnm   r19,r27,r12,21,26
5e640 rlwnm   r3,r27,r13,29,22
5e644 xoris   r18,r27,29440
0005e648 <init_cursor>:
5e648 mflr    r0
5e64c stwu    r1,-64(r1)
5e650 lwz     r4,36(r2)   ; TOC+36 -> D_5f00c
5e654 stw     r0,72(r1)
5e658 lbz     r0,0(r4)
5e65c cmpwi   cr1,r0,0
5e660 cmplwi  r0,1
5e664 bne     cr1,0x5e670
5e668 bl      0x5e6b4  <init_cursor_bt485>   ; call init_cursor_bt485(r3=?, r4=?, r5=?, r6=?)
5e66c b       0x5e680
5e670 bne     0x5e67c
5e674 bl      0x5e938  <init_cursor_rgb525>   ; call init_cursor_rgb525(r3=?, r4=?, r5=?, r6=?)
5e678 b       0x5e680
5e67c bl      0x5ece8  <init_cursor_s3dac>   ; call init_cursor_s3dac(r3=?, r4=?, r5=?, r6=?)
5e680 lwz     r12,72(r1)
5e684 addic   r1,r1,64
5e688 mtlr    r12
5e68c blr
5e690 .long 0x0
5e694 .long 0x2041
5e698 lwz     r0,256(0)
5e69c .long 0x0
5e6a0 .long 0x48
5e6a4 .long 0xb696e
5e6a8 xori    r20,r11,24419
5e6ac andis.  r18,r11,29551
5e6b0 andi.   r0,r16,0
0005e6b4 <init_cursor_bt485>:
5e6b4 stmw    r26,-24(r1)
5e6b8 mflr    r0
5e6bc mfcr    r12
5e6c0 lis     r5,512
5e6c4 stw     r12,4(r1)
5e6c8 stw     r0,8(r1)
5e6cc addi    r31,r3,0
5e6d0 addic   r29,r5,969
5e6d4 stwu    r1,-96(r1)
5e6d8 addi    r3,r29,0
5e6dc bl      0x5ad24  <s3_bt485_read>   ; call s3_bt485_read(r3=0x20003c9, r4=?, r5=0x2000000, r6=?)
5e6e0 lwz     r28,4(r2)   ; TOC+4 -> D_60480
5e6e4 clrlwi  r30,r3,24
5e6e8 lwz     r5,0(r28)
5e6ec li      r3,980
5e6f0 lwzu    r11,344(r5)
5e6f4 li      r4,66
5e6f8 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x42, r5=?)
5e6fc lwz     r2,20(r1)
5e700 lwz     r5,0(r28)
5e704 li      r3,981
5e708 lwzu    r11,324(r5)
5e70c bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5e710 lwz     r2,20(r1)
5e714 srwi    r5,r3,4
5e718 lwz     r6,44(r2)   ; TOC+44 -> D_5f014
5e71c mtcrf   1,r5
5e720 lwz     r5,3836(r6)
5e724 rlwinm  r26,r30,0,29,27
5e728 cmpw    r5,r31
5e72c bne     cr7,0x5e734
5e730 ori     r26,r30,8
5e734 beq     0x5e8dc
5e738 cmpwi   r31,0
5e73c lwz     r5,0(r28)
5e740 li      r3,968
5e744 li      r4,0
5e748 beq     0x5e8e8
5e74c stw     r31,3836(r6)
5e750 lwzu    r11,344(r5)
5e754 bl      0x59490   ; SVC out8(r3=0x3c8, r4=0x0, r5=?)
5e758 lwz     r2,20(r1)
5e75c lwz     r5,0(r28)
5e760 li      r3,980
5e764 lwzu    r11,344(r5)
5e768 li      r4,85
5e76c bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x55, r5=?)
5e770 lwz     r2,20(r1)
5e774 lwz     r5,0(r28)
5e778 li      r3,981
5e77c lwzu    r11,324(r5)
5e780 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5e784 lwz     r2,20(r1)
5e788 lwz     r5,0(r28)
5e78c clrrwi  r6,r3,1
5e790 ori     r4,r6,2
5e794 lwzu    r11,344(r5)
5e798 li      r3,981
5e79c bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5e7a0 lwz     r2,20(r1)
5e7a4 cmpwi   cr4,r31,3
5e7a8 cmpwi   cr2,r31,1
5e7ac cmpwi   cr3,r31,2
5e7b0 li      r27,0
5e7b4 addi    r30,r27,0
5e7b8 lwz     r5,0(r28)
5e7bc li      r3,967
5e7c0 lwzu    r11,344(r5)
5e7c4 addi    r4,r27,0
5e7c8 beq     cr2,0x5e84c
5e7cc beq     cr3,0x5e810
5e7d0 bne     cr4,0x5e860
5e7d4 cmpwi   r30,24
5e7d8 cmpwi   cr6,r30,20
5e7dc cmpwi   cr5,r30,16
5e7e0 beq     0x5e80c
5e7e4 cmpwi   r30,12
5e7e8 beq     cr6,0x5e80c
5e7ec cmpwi   cr6,r30,8
5e7f0 beq     cr5,0x5e80c
5e7f4 cmpwi   cr5,r30,4
5e7f8 beq     0x5e80c
5e7fc cmpwi   r30,0
5e800 beq     cr6,0x5e80c
5e804 beq     cr5,0x5e80c
5e808 bne     0x5e810
5e80c li      r4,255
5e810 cmpwi   cr5,r30,52
5e814 cmpwi   cr6,r30,48
5e818 cmpwi   r30,44
5e81c beq     cr5,0x5e848
5e820 cmpwi   cr5,r30,40
5e824 beq     cr6,0x5e848
5e828 cmpwi   cr6,r30,36
5e82c beq     0x5e848
5e830 cmpwi   r30,32
5e834 beq     cr5,0x5e848
5e838 cmpwi   cr5,r30,28
5e83c beq     cr6,0x5e848
5e840 beq     0x5e848
5e844 bne     cr5,0x5e84c
5e848 li      r4,255
5e84c cmpwi   r30,56
5e850 cmpwi   cr5,r30,60
5e854 beq     0x5e85c
5e858 bne     cr5,0x5e860
5e85c li      r4,255
5e860 bl      0x59490   ; SVC out8(r3=0x3c7, r4=0xff, r5=?)
5e864 lwz     r2,20(r1)
5e868 addic   r30,r30,1
5e86c cmpwi   r30,128
5e870 blt     0x5e7b8
5e874 lwz     r5,0(r28)
5e878 li      r3,967
5e87c lwzu    r11,344(r5)
5e880 li      r4,255
5e884 bl      0x59490   ; SVC out8(r3=0x3c7, r4=0xff, r5=?)
5e888 lwz     r2,20(r1)
5e88c addic   r27,r27,1
5e890 cmpwi   r27,128
5e894 blt     0x5e874
5e898 lwz     r5,0(r28)
5e89c li      r3,980
5e8a0 lwzu    r11,344(r5)
5e8a4 li      r4,85
5e8a8 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x55, r5=?)
5e8ac lwz     r2,20(r1)
5e8b0 lwz     r5,0(r28)
5e8b4 li      r3,981
5e8b8 lwzu    r11,324(r5)
5e8bc bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5e8c0 lwz     r2,20(r1)
5e8c4 lwz     r5,0(r28)
5e8c8 clrrwi  r4,r3,2
5e8cc lwzu    r11,344(r5)
5e8d0 li      r3,981
5e8d4 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5e8d8 lwz     r2,20(r1)
5e8dc cmpwi   r31,0
5e8e0 ori     r4,r26,2
5e8e4 bne     0x5e8ec
5e8e8 rlwinm  r4,r26,0,31,29
5e8ec addi    r3,r29,0
5e8f0 bl      0x5adf4  <s3_bt485_write>   ; call s3_bt485_write(r3=0x20003c9, r4=?, r5=?, r6=?)
5e8f4 lwz     r0,104(r1)
5e8f8 lwz     r12,100(r1)
5e8fc addic   r1,r1,96
5e900 mtcrf   56,r12
5e904 mtlr    r0
5e908 lmw     r26,-24(r1)
5e90c blr
5e910 .long 0x0
5e914 .long 0x2043
5e918 lwz     r0,256(r6)
5e91c .long 0x0
5e920 .long 0x25c
5e924 .long 0x11696e
5e928 xori    r20,r11,24419
5e92c andis.  r18,r11,29551
5e930 andi.   r31,r18,25204
5e934 addic.  r1,r24,13568
0005e938 <init_cursor_rgb525>:
5e938 stmw    r27,-20(r1)
5e93c mflr    r0
5e940 mfcr    r12
5e944 lwz     r31,4(r2)   ; TOC+4 -> D_60480
5e948 stw     r12,4(r1)
5e94c lwz     r8,0(r31)
5e950 stw     r0,8(r1)
5e954 addi    r30,r3,0
5e958 stwu    r1,-96(r1)
5e95c li      r3,980
5e960 li      r4,66
5e964 lwzu    r11,344(r8)
5e968 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x42, r5=?)
5e96c lwz     r2,20(r1)
5e970 lwz     r8,0(r31)
5e974 li      r3,981
5e978 lwzu    r11,324(r8)
5e97c bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5e980 lwz     r2,20(r1)
5e984 addi    r29,r3,0
5e988 li      r3,113
5e98c bl      0x5b098  <s3_rgb525_read>   ; call s3_rgb525_read(r3=0x71, r4=?, r5=?, r6=?)
5e990 srwi    r0,r29,4
5e994 mtcrf   1,r0
5e998 clrlwi  r29,r3,24
5e99c li      r3,113
5e9a0 bne     cr7,0x5e9a8
5e9a4 ori     r29,r29,32
5e9a8 addi    r4,r29,0
5e9ac bl      0x5b198  <s3_rgb525_write>   ; call s3_rgb525_write(r3=0x71, r4=?, r5=?, r6=?)
5e9b0 li      r3,48
5e9b4 bl      0x5b098  <s3_rgb525_read>   ; call s3_rgb525_read(r3=0x30, r4=?, r5=?, r6=?)
5e9b8 lwz     r9,44(r2)   ; TOC+44 -> D_5f014
5e9bc cmpwi   cr2,r30,0
5e9c0 lwz     r0,3840(r9)
5e9c4 rlwinm  r28,r3,0,24,29
5e9c8 cmpw    r0,r30
5e9cc beq     0x5ec44
5e9d0 lwz     r8,0(r31)
5e9d4 li      r3,968
5e9d8 li      r4,0
5e9dc beq     cr2,0x5ec50
5e9e0 stw     r30,3840(r9)
5e9e4 lwzu    r11,344(r8)
5e9e8 bl      0x59490   ; SVC out8(r3=0x3c8, r4=0x0, r5=?)
5e9ec lwz     r2,20(r1)
5e9f0 lwz     r8,0(r31)
5e9f4 li      r3,980
5e9f8 lwzu    r11,344(r8)
5e9fc li      r4,85
5ea00 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x55, r5=?)
5ea04 lwz     r2,20(r1)
5ea08 lwz     r8,0(r31)
5ea0c li      r3,981
5ea10 lwzu    r11,324(r8)
5ea14 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5ea18 lwz     r2,20(r1)
5ea1c lwz     r8,0(r31)
5ea20 ori     r0,r3,1
5ea24 rlwinm  r4,r0,0,31,29
5ea28 lwzu    r11,344(r8)
5ea2c li      r3,981
5ea30 bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5ea34 lwz     r2,20(r1)
5ea38 lwz     r8,0(r31)
5ea3c li      r3,968
5ea40 lwzu    r11,344(r8)
5ea44 li      r4,0
5ea48 bl      0x59490   ; SVC out8(r3=0x3c8, r4=0x0, r5=?)
5ea4c lwz     r2,20(r1)
5ea50 lwz     r8,0(r31)
5ea54 li      r3,969
5ea58 lwzu    r11,344(r8)
5ea5c li      r4,1
5ea60 bl      0x59490   ; SVC out8(r3=0x3c9, r4=0x1, r5=?)
5ea64 lwz     r2,20(r1)
5ea68 lwz     r8,0(r31)
5ea6c li      r3,967
5ea70 lwzu    r11,344(r8)
5ea74 li      r4,1
5ea78 bl      0x59490   ; SVC out8(r3=0x3c7, r4=0x1, r5=?)
5ea7c lwz     r2,20(r1)
5ea80 cmpwi   cr4,r30,3
5ea84 cmpwi   cr3,r30,2
5ea88 li      r27,0
5ea8c lwz     r8,0(r31)
5ea90 li      r3,966
5ea94 lwzu    r11,344(r8)
5ea98 li      r4,170
5ea9c beq     cr2,0x5ebbc
5eaa0 cmpwi   r30,1
5eaa4 beq     0x5eb98
5eaa8 beq     cr3,0x5eb24
5eaac bne     cr4,0x5ebbc
5eab0 cmpwi   cr6,r27,48
5eab4 cmpwi   r27,40
5eab8 cmpwi   cr5,r27,32
5eabc cmpwi   cr1,r27,49
5eac0 beq     cr6,0x5eb20
5eac4 cmpwi   cr6,r27,41
5eac8 beq     0x5eb20
5eacc cmpwi   r27,33
5ead0 beq     cr5,0x5eb20
5ead4 cmpwi   cr5,r27,24
5ead8 beq     cr1,0x5eb20
5eadc cmpwi   cr1,r27,16
5eae0 beq     cr6,0x5eb20
5eae4 cmpwi   cr6,r27,8
5eae8 beq     0x5eb20
5eaec cmpwi   r27,0
5eaf0 beq     cr5,0x5eb20
5eaf4 cmpwi   cr5,r27,25
5eaf8 beq     cr1,0x5eb20
5eafc cmpwi   cr1,r27,17
5eb00 beq     cr6,0x5eb20
5eb04 cmpwi   cr6,r27,9
5eb08 beq     0x5eb20
5eb0c cmpwi   r27,1
5eb10 beq     cr5,0x5eb20
5eb14 beq     cr1,0x5eb20
5eb18 beq     cr6,0x5eb20
5eb1c bne     0x5eb24
5eb20 li      r4,255
5eb24 cmpwi   cr6,r27,104
5eb28 cmpwi   r27,96
5eb2c cmpwi   cr5,r27,88
5eb30 cmpwi   cr1,r27,105
5eb34 beq     cr6,0x5eb94
5eb38 cmpwi   cr6,r27,97
5eb3c beq     0x5eb94
5eb40 cmpwi   r27,89
5eb44 beq     cr5,0x5eb94
5eb48 cmpwi   cr5,r27,80
5eb4c beq     cr1,0x5eb94
5eb50 cmpwi   cr1,r27,72
5eb54 beq     cr6,0x5eb94
5eb58 cmpwi   cr6,r27,64
5eb5c beq     0x5eb94
5eb60 cmpwi   r27,56
5eb64 beq     cr5,0x5eb94
5eb68 cmpwi   cr5,r27,81
5eb6c beq     cr1,0x5eb94
5eb70 cmpwi   cr1,r27,73
5eb74 beq     cr6,0x5eb94
5eb78 cmpwi   cr6,r27,65
5eb7c beq     0x5eb94
5eb80 cmpwi   r27,57
5eb84 beq     cr5,0x5eb94
5eb88 beq     cr1,0x5eb94
5eb8c beq     cr6,0x5eb94
5eb90 bne     0x5eb98
5eb94 li      r4,255
5eb98 cmpwi   cr6,r27,112
5eb9c cmpwi   cr1,r27,120
5eba0 cmpwi   r27,113
5eba4 cmpwi   cr5,r27,121
5eba8 beq     cr6,0x5ebb8
5ebac beq     cr1,0x5ebb8
5ebb0 beq     0x5ebb8
5ebb4 bne     cr5,0x5ebbc
5ebb8 li      r4,255
5ebbc bl      0x59490   ; SVC out8(r3=0x3c6, r4=0xff, r5=?)
5ebc0 lwz     r2,20(r1)
5ebc4 addic   r27,r27,1
5ebc8 cmpwi   r27,256
5ebcc blt     0x5ea8c
5ebd0 lwz     r8,0(r31)
5ebd4 li      r3,967
5ebd8 lwzu    r11,344(r8)
5ebdc li      r4,0
5ebe0 bl      0x59490   ; SVC out8(r3=0x3c7, r4=0x0, r5=?)
5ebe4 lwz     r2,20(r1)
5ebe8 lwz     r8,0(r31)
5ebec addi    r4,r29,0
5ebf0 lwzu    r11,344(r8)
5ebf4 li      r3,969
5ebf8 bl      0x59490   ; SVC out8(r3=0x3c9, r4=?, r5=?)
5ebfc lwz     r2,20(r1)
5ec00 lwz     r8,0(r31)
5ec04 li      r3,980
5ec08 lwzu    r11,344(r8)
5ec0c li      r4,85
5ec10 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x55, r5=?)
5ec14 lwz     r2,20(r1)
5ec18 lwz     r8,0(r31)
5ec1c li      r3,981
5ec20 lwzu    r11,324(r8)
5ec24 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5ec28 lwz     r2,20(r1)
5ec2c lwz     r8,0(r31)
5ec30 clrrwi  r4,r3,2
5ec34 lwzu    r11,344(r8)
5ec38 li      r3,981
5ec3c bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5ec40 lwz     r2,20(r1)
5ec44 ori     r0,r28,2
5ec48 beq     cr2,0x5ec50
5ec4c clrlwi  r28,r0,24
5ec50 addi    r4,r28,0
5ec54 li      r3,48
5ec58 bl      0x5b198  <s3_rgb525_write>   ; call s3_rgb525_write(r3=0x30, r4=?, r5=?, r6=?)
5ec5c lwz     r8,0(r31)
5ec60 li      r3,980
5ec64 lwzu    r11,344(r8)
5ec68 li      r4,69
5ec6c bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x45, r5=?)
5ec70 lwz     r2,20(r1)
5ec74 lwz     r8,0(r31)
5ec78 li      r3,981
5ec7c addi    r9,r8,0
5ec80 lwzu    r31,344(r9)
5ec84 lwzu    r11,324(r8)
5ec88 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5ec8c lwz     r2,20(r1)
5ec90 ori     r4,r3,32
5ec94 addi    r11,r31,0
5ec98 li      r3,981
5ec9c bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5eca0 lwz     r2,20(r1)
5eca4 lwz     r0,104(r1)
5eca8 lwz     r12,100(r1)
5ecac addic   r1,r1,96
5ecb0 mtcrf   56,r12
5ecb4 mtlr    r0
5ecb8 lmw     r27,-20(r1)
5ecbc blr
5ecc0 .long 0x0
5ecc4 .long 0x2043
5ecc8 lwz     r0,256(r5)
5eccc .long 0x0
5ecd0 .long 0x388
5ecd4 .long 0x12696e
5ecd8 xori    r20,r11,24419
5ecdc andis.  r18,r11,29551
5ece0 andi.   r31,r18,29287
5ece4 ori     r21,r17,12853
0005ece8 <init_cursor_s3dac>:
5ece8 mflr    r0
5ecec mfcr    r12
5ecf0 stmw    r29,-12(r1)
5ecf4 stw     r12,4(r1)
5ecf8 stw     r0,8(r1)
5ecfc stwu    r1,-80(r1)
5ed00 addi    r31,r3,0
5ed04 bl      0x5b608  <s3_get_base_address>   ; call s3_get_base_address(r3=?, r4=?, r5=?, r6=?)
5ed08 lwz     r29,4(r2)   ; TOC+4 -> D_60480
5ed0c addi    r30,r3,0
5ed10 lwz     r4,0(r29)
5ed14 li      r3,980
5ed18 lwzu    r11,344(r4)
5ed1c li      r4,54
5ed20 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x36, r5=?)
5ed24 lwz     r2,20(r1)
5ed28 lwz     r4,0(r29)
5ed2c li      r3,981
5ed30 lwzu    r11,324(r4)
5ed34 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5ed38 lwz     r2,20(r1)
5ed3c srwi    r3,r3,6
5ed40 subfic  r6,r3,4
5ed44 slwi    r3,r6,20
5ed48 addic   r3,r3,-2048
5ed4c addc    r30,r3,r30
5ed50 bl      0x5cc68  <ge_wait>   ; call ge_wait(r3=?, r4=?, r5=?, r6=?)
5ed54 li      r3,256
5ed58 cmpwi   r31,3
5ed5c cmpwi   cr4,r31,0
5ed60 cmpwi   cr5,r31,1
5ed64 cmpwi   cr1,r31,2
5ed68 mtctr   r3
5ed6c li      r3,980
5ed70 li      r4,69
5ed74 li      r8,0
5ed78 li      r6,0
5ed7c li      r11,255
5ed80 li      r9,0
5ed84 beq     cr4,0x5ee20
5ed88 beq     cr5,0x5ee0c
5ed8c beq     cr1,0x5edd0
5ed90 bne     0x5ee20
5ed94 cmpwi   cr6,r6,0
5ed98 cmplwi  cr3,r6,4
5ed9c cmplwi  cr7,r6,8
5eda0 beq     cr6,0x5edcc
5eda4 cmplwi  cr6,r6,12
5eda8 beq     cr3,0x5edcc
5edac cmplwi  cr3,r6,16
5edb0 beq     cr7,0x5edcc
5edb4 cmplwi  cr7,r6,20
5edb8 beq     cr6,0x5edcc
5edbc cmplwi  cr6,r6,24
5edc0 beq     cr3,0x5edcc
5edc4 beq     cr7,0x5edcc
5edc8 bne     cr6,0x5edd0
5edcc li      r9,255
5edd0 cmplwi  cr7,r6,28
5edd4 cmplwi  cr3,r6,32
5edd8 cmplwi  cr6,r6,36
5eddc beq     cr7,0x5ee08
5ede0 cmplwi  cr7,r6,40
5ede4 beq     cr3,0x5ee08
5ede8 cmplwi  cr3,r6,44
5edec beq     cr6,0x5ee08
5edf0 cmplwi  cr6,r6,48
5edf4 beq     cr7,0x5ee08
5edf8 cmplwi  cr7,r6,52
5edfc beq     cr3,0x5ee08
5ee00 beq     cr6,0x5ee08
5ee04 bne     cr7,0x5ee0c
5ee08 li      r9,255
5ee0c cmplwi  cr6,r6,56
5ee10 cmplwi  cr7,r6,60
5ee14 beq     cr6,0x5ee1c
5ee18 bne     cr7,0x5ee20
5ee1c li      r9,255
5ee20 stb     r9,2(r30)
5ee24 stb     r11,0(r30)
5ee28 stb     r11,1(r30)
5ee2c stb     r8,3(r30)
5ee30 addic   r30,r30,4
5ee34 addic   r6,r6,1
5ee38 bdnz    0x5ed80
5ee3c lwz     r6,0(r29)
5ee40 lwzu    r11,344(r6)
5ee44 bl      0x59490   ; SVC out8(r3=0x3d4, r4=0x45, r5=?)
5ee48 lwz     r2,20(r1)
5ee4c lwz     r4,0(r29)
5ee50 li      r3,981
5ee54 lwzu    r11,324(r4)
5ee58 bl      0x59490   ; SVC in8(r3=0x3d5, r4=?, r5=?)
5ee5c lwz     r2,20(r1)
5ee60 bne     cr4,0x5ee6c
5ee64 clrrwi  r4,r3,1
5ee68 b       0x5ee70
5ee6c ori     r4,r3,1
5ee70 lwz     r6,0(r29)
5ee74 li      r3,981
5ee78 lwzu    r11,344(r6)
5ee7c bl      0x59490   ; SVC out8(r3=0x3d5, r4=?, r5=?)
5ee80 lwz     r2,20(r1)
5ee84 lwz     r0,88(r1)
5ee88 lwz     r12,84(r1)
5ee8c addic   r1,r1,80
5ee90 mtcrf   24,r12
5ee94 mtlr    r0
5ee98 lmw     r29,-12(r1)
5ee9c blr
5eea0 .long 0x0
5eea4 .long 0x2043
5eea8 lwz     r0,256(r3)
5eeac .long 0x0
5eeb0 .long 0x1b8
5eeb4 .long 0x11696e
5eeb8 xori    r20,r11,24419
5eebc andis.  r18,r11,29551
5eec0 andi.   r31,r18,29491
5eec4 oris    r1,r3,25344
0005eec8 <s3_cursor_size>:
5eec8 mflr    r0
5eecc stmw    r30,-8(r1)
5eed0 lwz     r31,44(r2)   ; TOC+44 -> D_5f014
5eed4 stw     r0,8(r1)
5eed8 stwu    r1,-80(r1)
5eedc li      r4,1
5eee0 lwz     r0,3520(r31)
5eee4 cmpwi   r0,0
5eee8 bne     0x5ef08
5eeec stw     r4,3520(r31)
5eef0 lwz     r30,3844(r31)
5eef4 stw     r3,3844(r31)
5eef8 bl      0x5e648  <init_cursor>   ; call init_cursor(r3=?, r4=0x1, r5=?, r6=?)
5eefc li      r0,0
5ef00 stw     r0,3520(r31)
5ef04 addi    r3,r30,0
5ef08 lwz     r12,88(r1)
5ef0c addic   r1,r1,80
5ef10 mtlr    r12
5ef14 lmw     r30,-8(r1)
5ef18 blr
5ef1c .long 0x0
5ef20 .long 0x2041
5ef24 lwz     r0,256(r2)   ; TOC+256 -> D_58f1c
5ef28 .long 0x0
5ef2c .long 0x54
5ef30 .long 0xe7333
5ef34 rlwnm   r3,r27,r14,21,25
5ef38 andi.   r15,r27,29279
5ef3c andi.   r9,r27,31333
5ef40 .long 0x0
5ef44 .long 0x90
5ef48 .long 0x9c
5ef4c .long 0xa8
5ef50 .long 0xb4
5ef54 .long 0xc0
5ef58 .long 0xcc
5ef5c .long 0x408
5ef60 .long 0x3b8
5ef64 .long 0x3b8
5ef68 .long 0x3b8
5ef6c .long 0x408
5ef70 .long 0x3b8
5ef74 .long 0x3b8
5ef78 .long 0x3b8
5ef7c .long 0x3b8
5ef80 .long 0x3b8
5ef84 .long 0x3b8
5ef88 .long 0x3b8
5ef8c .long 0x3b8
5ef90 .long 0x3b8
5ef94 .long 0x3b8
5ef98 .long 0x3b8
5ef9c .long 0x400
5efa0 .long 0x3b8
5efa4 .long 0x3b8
5efa8 .long 0x3b8
5efac .long 0x3b8
5efb0 .long 0x3b8
5efb4 .long 0x3b8
5efb8 .long 0x3b8
5efbc .long 0x3b8
5efc0 .long 0x400
5efc4 .long 0x380
5efc8 .long 0x3b8
5efcc .long 0x3b8
5efd0 .long 0x3b8
5efd4 .long 0x3b8
5efd8 .long 0x388
5efdc .long 0x3b8
5efe0 .long 0x388
5efe4 .long 0x1f0
5efe8 .long 0x240
5efec .long 0x1f8
5eff0 .long 0x210
5eff4 .long 0x204
5eff8 .long 0x21c
5effc .long 0x224
6bec0 
00100918:  00 00 02 38  
