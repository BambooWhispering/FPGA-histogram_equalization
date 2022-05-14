/*
单通道的灰度直方图均衡化

将8位灰度图像按帧进行灰度直方图均衡化
*/
module histogram_equalization(
	// 系统信号
	pclk				,	// 像素时钟（pixel clock）
	rst_n				,	// 复位（reset）
	
	// 灰度直方图未处理前的源视频信号
	src_hs_hsync		,	// 源视频 行同步信号（数据有效输出中标志）
	src_hs_vsync		,	// 源视频 场同步信号
	src_hs_data_out		,	// 源视频 像素数据输出
	
	// 灰度直方图均衡化后的目的视频信号
	dst_he_hsync		,	// 直方图均衡化后的目的视频 行同步信号（数据有效输出中标志）
	dst_he_vsync		,	// 直方图均衡化后的目的视频 场同步信号
	dst_he_data_out		 	// 直方图均衡化后的目的视频 当前像素值
	);
	
	// ******************************************参数声明****************************************
	// 图像基本参数
	parameter	IW				=	'd640	;	// 图像宽（image width）
	parameter	IH				=	'd480	;	// 图像高（image height）
	
	// 灰度直方图统计前的源视频参数
	parameter	SRC_HS_DW		=	'd8		;	// 灰度直方图统计前的源视频像素数据位宽
	// 灰度直方图统计后的统计结果参数
	parameter	HS_CNT_DW		=	'd32	;	// 灰度直方图统计后的统计结果像素数据个数位宽（至少要比IW*IH的位宽大）
	
	// 调试辅助信号（仅调试时可使用）
	parameter	HS_RESULT_STORE	=	1'b1	;	// 是否将直方图均衡化前的统计结果存储到磁盘中（写到.txt文件中）
	parameter	HE_RESULT_STORE	=	1'b1	;	// 是否将直方图均衡化后的统计结果存储到磁盘中（写到.txt文件中）
	parameter	HS_FILE_ADDR	=	"D:/FPGA_learning/Projects/08_ImageProcessing/04_simulation_platform_histogram_equalization_2/doc/hs/hs_pixel_cnt.txt";	// 直方图均衡化前的统计结果文件保存位置
	parameter	HE_FILE_ADDR	=	"D:/FPGA_learning/Projects/08_ImageProcessing/04_simulation_platform_histogram_equalization_2/doc/he/he_pixel_cnt.txt";	// 直方图均衡化前的统计结果文件保存位置
	// ******************************************************************************************
	
	
	// *******************************************端口声明***************************************
	// 系统信号
	input							pclk				;	// 像素时钟（pixel clock）
	input							rst_n				;	// 复位（reset）
	
	// 灰度直方图未处理前的源视频信号
	input							src_hs_hsync		;	// 源视频 行同步信号（数据有效输出中标志）
	input							src_hs_vsync		;	// 源视频 场同步信号
	input		[SRC_HS_DW-1:0]		src_hs_data_out		;	// 源视频 像素数据输出
	
	// 灰度直方图均衡化后的目的视频信号
	output							dst_he_hsync		;	// 直方图均衡化后的目的视频 行同步信号（数据有效输出中标志）
	output							dst_he_vsync		;	// 直方图均衡化后的目的视频 场同步信号
	output		[SRC_HS_DW-1:0]		dst_he_data_out		; 	// 直方图均衡化后的目的视频 当前像素值
	// *******************************************************************************************
	
	
	// ******************************************内部信号声明*************************************
	// 灰度直方图统计后的统计结果
	wire							hs_request			;	// 直方图统计结果 输出请求（一个时钟周期的脉冲）
	wire							hs_valid			;	// 直方图统计结果 有效输出中标志
	wire		[SRC_HS_DW-1:0]		hs_pixel			; 	// 直方图统计结果 当前像素值
	wire		[HS_CNT_DW-1:0]		hs_pixel_cnt		; 	// 直方图统计结果 当前像素值像素点个数（顺序输出 像素值为0,1,...,255的个数）
	wire							result_rd_ready		;	// 直方图统计结果 读准备就绪标志（一个时钟周期的脉冲）（可作为 直方图统计结果 输出请求）
	
	// 直方图均衡化中间结果
	reg			[HS_CNT_DW-1:0]		sum_pixel_cnt		;	// 像素个数累加和
	reg			[HS_CNT_DW-1:0]		sum_l_shift_5		;	// 像素个数累加和左移5位
	reg			[HS_CNT_DW-1:0]		sum_l_shift_4		;	// 像素个数累加和左移4位
	reg			[HS_CNT_DW-1:0]		sum_l_shift_2		;	// 像素个数累加和左移2位
	reg			[HS_CNT_DW-1:0]		sum_l_shift_1		;	// 像素个数累加和左移1位
	reg			[HS_CNT_DW-1:0]		sum_r_shift_3		;	// 像素个数累加和右移3位
	reg			[HS_CNT_DW-1:0]		sum_r_shift_4		;	// 像素个数累加和右移4位
	reg			[HS_CNT_DW-1:0]		add_ls5_ls4			;	// 像素个数累加和左移5位 与 像素个数累加和左移4位 的和
	reg			[HS_CNT_DW-1:0]		add_ls2_ls1			;	// 像素个数累加和左移2位 与 像素个数累加和左移1位 的和
	reg			[HS_CNT_DW-1:0]		add_rs3_rs4			;	// 像素个数累加和右移3位 与 像素个数累加和右移4位 的和
	reg			[HS_CNT_DW-1:0]		add_temp1			;	// 上一级流水线相邻数据相加的和1
	reg			[HS_CNT_DW-1:0]		add_temp2			;	// 上一级流水线相邻数据相加的和2
	reg			[HS_CNT_DW-1:0]		add_temp3			;	// 上一级流水线相邻数据相加的和3
	reg			[HS_CNT_DW-1:0]		div_temp			;	// 临时除法（移位）结果
	
	// 双口RAM：用于存储映射后的灰度级（比如直方图均衡化后，原来灰度值为2的像素点变为了3）
	wire							ramA_rd_en			;	// A端口（设置为只读）读使能
	wire		[SRC_HS_DW-1:0]		ramA_rd_addr		;	// A端口（设置为只读）读地址
	wire		[HS_CNT_DW-1:0]		ramA_rd_data		;	// A端口（设置为只读）读数据
	wire							ramB_wr_en			;	// B端口（设置为只写）写使能
	wire		[SRC_HS_DW-1:0]		ramB_wr_addr		;	// B端口（设置为只写）写地址
	wire		[HS_CNT_DW-1:0]		ramB_wr_data		;	// B端口（设置为只写）写数据
	reg								ramA_rd_valid		;	// A端口可读标志
	
	reg			[5:0]				hs_valid_r_arr		;	// 直方图统计结果有效输出中标志 打6拍的数组
	reg			[SRC_HS_DW-1:0]		hs_pixel_r_arr[5:0]	;	// 直方图统计结果当前像素值 打6拍的数组
	
	// 源视频信号打拍
	reg								src_hs_vsync_r1		;	// 源视频场同步信号 打1拍
	reg								src_hs_hsync_r1		;	// 源视频行同步信号（数据有效输出中标志） 打1拍
	wire							src_hs_vsync_neg	;	// 源视频场同步信号 下降沿
	
	// for循环计数值
	integer							i					;	// for循环计数值
	
	// 调试参数
	integer							fid					;	// 文件指针
	// *******************************************************************************************
	
	
	// ******************************************灰度直方图统计***********************************
	// 单通道的灰度直方图统计
	histogram_statistics #(
		// 灰度直方图统计前的源视频参数
		.SRC_HS_DW			(SRC_HS_DW			),	// 灰度直方图统计前的源视频像素数据位宽
		
		// 灰度直方图统计后的统计结果参数
		.HS_CNT_DW			(HS_CNT_DW			),	// 灰度直方图统计后的统计结果像素数据个数位宽
		
		// 调试辅助信号（仅调试时可使用）
		.HS_RESULT_STORE	(1'b1				),	// 是否将直方图统计结果存储到磁盘中（写到.txt文件中）
		.FILE_ADDR			(HS_FILE_ADDR		)	// 统计结果文件保存位置
		)
	histogram_statistics_u0(
		// 系统信号
		.pclk				(pclk				),	// 像素时钟（pixel clock）
		.rst_n				(rst_n				),	// 复位（reset）
		
		// 灰度直方图统计前的源视频信号
		.src_hs_hsync		(src_hs_hsync		),	// 源视频 行同步信号（数据有效输出中标志）
		.src_hs_vsync		(src_hs_vsync		),	// 源视频 场同步信号
		.src_hs_data_out	(src_hs_data_out	),	// 源视频 像素数据输出
		
		// 灰度直方图统计后的统计结果
		.hs_request			(hs_request			),	// 直方图统计结果 输出请求（一个时钟周期的脉冲）
		.hs_valid			(hs_valid			),	// 直方图统计结果 有效输出中标志
		.hs_pixel			(hs_pixel			),	// 直方图统计结果 当前像素值
		.hs_pixel_cnt		(hs_pixel_cnt		),	// 直方图统计结果 当前像素值像素点个数（顺序输出 像素值为0,1,...,255的个数）
		.result_rd_ready	(result_rd_ready	),	// 直方图统计结果 读准备就绪标志（一个时钟周期的脉冲）（可作为 直方图统计结果 输出请求）
		.result_wr_done		(					)	// 直方图统计结果 写入完成标志（一个时钟周期的脉冲）
		);
	assign	hs_request	=	result_rd_ready	;
	// *******************************************************************************************
	
	
	// *********************************计算直方图均衡和后的灰度级映射****************************
	
	// 第一级流水线：计算 直方图统计结果累加
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
			sum_pixel_cnt <= 1'b0;
		else if(hs_valid)
			sum_pixel_cnt <= sum_pixel_cnt + hs_pixel_cnt;
		else
			sum_pixel_cnt <= 1'b0;
	end
	
	// ---计算 累加和 * (L-1)/(M*N)
	// 因为FPGA不擅长除法，所以这里采取的方法是舍弃一部分精度，化除法运算为移位、加法运算
	// （用generate的好处是，只生成满足条件的电路，也就是这里虽然定义了多种规格情况下的电路，但在编译中只会生成唯一一个满足条件的电路，而if则是都生成）
	generate
	begin
		
		// ---灰度级位宽：8位		图像大小：640*480---
		/*
		sum * (2^8-1)/(640*480)
		= sum * 255/(640*480)
		= sum * 17/20480
		= sum * (2^4 + 2^0)/(2^14 + 2^12)
		= sum * (2^4 + 2^0)/(2^12 * 5)
		= sum * ((2^4 + 2^0)/(2^12 * 2^4)) * ((2^4)/5)
		= sum * ((2^4 + 2^0)/(2^16)) * 3.2
		= sum * ((2^4 + 2^0)/(2^16)) * (2^1 + 2^0 + 2^-3 + 2^-4)
		= sum * (2^5 + 2^4 + 2^2 + 2^1 + 2^-3 + 2^-4) / (2^16)
		= (sum<<5 + sum<<4 + sum<<2 + sum<<1 + sum>>3 + sum>>4) >>16
		*/
		if(SRC_HS_DW=='d8 && IW=='d640 && IH=='d480)
		begin: DIV_DW8_IW640_IH480
			// 第二级流水线：移位
			always @(posedge pclk, negedge rst_n)
			begin
				if(!rst_n)
				begin
					sum_l_shift_5 <= 1'b0;
					sum_l_shift_4 <= 1'b0;
					sum_l_shift_2 <= 1'b0;
					sum_l_shift_1 <= 1'b0;
					sum_r_shift_3 <= 1'b0;
					sum_r_shift_4 <= 1'b0;
				end
				else
				begin
					sum_l_shift_5 <= sum_pixel_cnt<<5;
					sum_l_shift_4 <= sum_pixel_cnt<<4;
					sum_l_shift_2 <= sum_pixel_cnt<<2;
					sum_l_shift_1 <= sum_pixel_cnt<<1;
					sum_r_shift_3 <= sum_pixel_cnt>>3;
					sum_r_shift_4 <= sum_pixel_cnt>>4;
				end
			end
			// 第三级流水线：加法
			always @(posedge pclk, negedge rst_n)
			begin
				if(!rst_n)
				begin
					add_ls5_ls4 <= 1'b0;
					add_ls2_ls1 <= 1'b0;
					add_rs3_rs4 <= 1'b0;
				end
				else
				begin
					add_ls5_ls4 <= sum_l_shift_5 + sum_l_shift_4;
					add_ls2_ls1 <= sum_l_shift_2 + sum_l_shift_1;
					add_rs3_rs4 <= sum_r_shift_3 + sum_r_shift_4;
				end
			end
			// 第四级流水线：加法
			always @(posedge pclk, negedge rst_n)
			begin
				if(!rst_n)
				begin
					add_temp1 <= 1'b0;
					add_temp2 <= 1'b0;
				end
				else
				begin
					add_temp1 <= add_ls5_ls4 + add_ls2_ls1;
					add_temp2 <= add_rs3_rs4;
				end
			end
			// 第五级流水线：加法
			always @(posedge pclk, negedge rst_n)
			begin
				if(!rst_n)
					add_temp3 <= 1'b0;
				else
					add_temp3 <= add_temp1 + add_temp2;
			end
			// 第六级流水线：右移16位
			always @(posedge pclk, negedge rst_n)
			begin
				if(!rst_n)
					div_temp <= 1'b0;
				else
					div_temp <= add_temp3>>16;
			end
		end
		// ---
		
	end	
	endgenerate
	
	// ---
	// *******************************************************************************************
	
	
	// *********************************双口RAM：用于存储映射后的灰度级***************************
	// 双口RAM：用于存储映射后的灰度级（比如直方图均衡化后，原来灰度值为2的像素点变为了3）
	ram_2port ram_2port_u2(
		// 系统信号
		.clock				(pclk				),	// 同步时钟
		
		// A端口（可读可写，这里只作为读）
		.address_a			(ramA_rd_addr		),
		.wren_a				(					),
		.data_a				(					),
		.rden_a				(ramA_rd_en			),
		.q_a				(ramA_rd_data		),		
		
		// B端口（可读可写，这里只作为写）
		.address_b			(ramB_wr_addr		),
		.wren_b				(ramB_wr_en			),
		.data_b				(ramB_wr_data		),
		.rden_b				(					),
		.q_b				(					)
		);
	
	// 直方图统计结果有效输出中标志、直方图统计结果当前像素值 打6拍
	// （因为从直方图统计结果输出，到直方图均衡化后的映射结果输出，经过了最多6级流水线）
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
		begin
			hs_valid_r_arr <= 1'b0;
			for(i=0; i<6; i=i+1)
				hs_pixel_r_arr[i] <= 1'b0;
		end
		else
		begin
			hs_valid_r_arr <= {hs_valid_r_arr[4:0], hs_valid};
			hs_pixel_r_arr[0] <= hs_pixel;
			for(i=1; i<6; i=i+1)
				hs_pixel_r_arr[i] <= hs_pixel_r_arr[i-1];
		end
	end
	
	
	// 双口RAM B端口写信号连接（存储映射后的灰度级）
	generate
	begin
		
		// ---灰度级位宽：8位		图像大小：640*480---
		if(SRC_HS_DW=='d8 && IW=='d640 && IH=='d480)
		begin: WR_DW8_IW640_IH480
			assign	ramB_wr_en		=	hs_valid_r_arr[5]	;	// B端口的写使能 为 直方图统计结果有效输出中标志打6拍
			assign	ramB_wr_addr	=	hs_pixel_r_arr[5]	;	// B端口的写地址 为 直方图统计结果当前像素值 打6拍
			assign	ramB_wr_data	=	div_temp			;	// B端口的写数据 为 累加和 * (L-1)/(M*N)
		end
		// ---
	
	end
	endgenerate
	
	
	// 源视频行同步信号、场同步信号打1拍
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
		begin
			src_hs_vsync_r1 <= 1'b0;
			src_hs_hsync_r1 <= 1'b0;
		end
		else
		begin
			src_hs_vsync_r1 <= src_hs_vsync;
			src_hs_hsync_r1 <= src_hs_hsync;
		end
	end
	// 源视频信号场同步信号下降沿
	assign	src_hs_vsync_neg	=	src_hs_vsync_r1 && ~src_hs_vsync	;	// 10
	// A端口可读标志
	// 因为相邻2帧的图像往往是相似的，故为了减少开销，我们采取的是 伪直方图均衡化
	// 也就是说，用上一帧的均衡化映射参数，去均衡化（更新）当前帧的图像
	// 故，起码要等第一帧流过并得到均衡化映射参数后，才可以开始对第2、3、...帧图像进行均衡化操作
	// 所以均衡化映射参数要在第1帧结束（一次场同步信号下降沿）后，才能从RAM中读出
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
			ramA_rd_valid <= 1'b0;
		else if(src_hs_vsync_neg) // 一次场同步信号下降沿后，A端口可读标志就一直为1了
			ramA_rd_valid <= 1'b1;
	end
	// A端口读信号连接（根据源视频像素值，查找输出映射后的目的视频像素值）
	assign	ramA_rd_en		=	src_hs_hsync && ramA_rd_valid			;	// A端口读使能 为 第一帧后的每一帧的行同步信号有效期间
	assign	ramA_rd_addr	=	ramA_rd_valid ? src_hs_data_out : 1'b0	;	// A端口读地址 为 第一帧后的每一帧的像素数据输出
	// *******************************************************************************************
	
	
	// ************************************均衡化后的目的数据流***********************************
	// 因为从RAM中读取出映射后的像素值会有1拍的延时，所以，目的视频的行同步、场同步信号要比源视频滞后1拍
	// 且，从第2帧开始才有均衡化后的数据
	assign	dst_he_vsync	=	src_hs_vsync_r1 && ramA_rd_valid		;
	assign	dst_he_hsync	=	src_hs_hsync_r1 && ramA_rd_valid		;
	assign	dst_he_data_out	=	ramA_rd_data							;
	// *******************************************************************************************
	
	
	// *************************将映射后的直方图存储到磁盘（写进.txt文件）************************
	// 是否将直方图均衡化的直方图结果存储到磁盘中（写到.txt文件中）信号 有效时，将映射后的直方图写入.txt文件
	generate
	begin
		
		// ---灰度级位宽：8位		图像大小：640*480---
		if(HE_RESULT_STORE && SRC_HS_DW=='d8 && IW=='d640 && IH=='d480) // 存储调试信号有效时，将直方图统计结果写入.txt文件
		begin: he_store
			always @(posedge pclk, negedge rst_n)
			begin
				if(!rst_n)
					fid = 0;
				else if(~hs_valid_r_arr[4] && hs_valid_r_arr[3]) // 打开文件
					fid = $fopen(HE_FILE_ADDR, "w"); // 以只写的方式打开文本文件，文件不存在则创建
				else if(ramB_wr_en) // 将映射后的灰度直方图写入磁盘文件中
					$fdisplay(fid, "%d", ramB_wr_data);
				else if(hs_valid_r_arr[5] && ~hs_valid_r_arr[0]) // 关闭文件
					$fclose(fid);
				else
					fid = 0;
			end
		end
		// ------
		
	end
	endgenerate
	// *******************************************************************************************
	
endmodule
