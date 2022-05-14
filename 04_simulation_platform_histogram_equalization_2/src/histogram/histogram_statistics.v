/*
单通道的灰度直方图统计

将8位灰度图像按帧进行灰度直方图统计，
当统计结果输出请求有效时，按顺序输出上一帧图像像素值为0,1,...,255时的像素个数。
若调试辅助信号有效，则还要将统计结果存储到磁盘中
*/
module histogram_statistics(
	// 系统信号
	pclk				,	// 像素时钟（pixel clock）
	rst_n				,	// 复位（reset）
	
	// 灰度直方图统计前的源视频信号
	src_hs_hsync		,	// 源视频 行同步信号（数据有效输出中标志）
	src_hs_vsync		,	// 源视频 场同步信号
	src_hs_data_out		,	// 源视频 像素数据输出
	
	// 灰度直方图统计后的统计结果
	hs_request			,	// 直方图统计结果 输出请求（一个时钟周期的脉冲）
	hs_valid			,	// 直方图统计结果 有效输出中标志
	hs_pixel			,	// 直方图统计结果 当前输出的像素值
	hs_pixel_cnt		,	// 直方图统计结果 当前输出的像素值的像素个数
	result_rd_ready		,	// 直方图统计结果 读准备就绪标志（一个时钟周期的脉冲）（可作为 直方图统计结果 输出请求）
	result_wr_done			// 直方图统计结果 写入完成标志（一个时钟周期的脉冲）
	);
	
	
	// ******************************************参数声明****************************************
	// 灰度直方图统计前的源视频参数
	parameter	SRC_HS_DW		=	'd8				;	// 灰度直方图统计前的源视频像素数据位宽
	parameter	SRC_HS_DCNT		=	'd1<<SRC_HS_DW	;	// 灰度直方图统计前的源视频像素数据个数
	
	// 灰度直方图统计后的统计结果参数
	parameter	HS_CNT_DW		=	'd32			;	// 灰度直方图统计后的统计结果像素数据个数位宽（至少要比IW*IH的位宽大）
	
	// 调试辅助信号（仅调试时可使用）
	parameter	HS_RESULT_STORE	=	1'b1			;	// 是否将直方图统计结果存储到磁盘中（写到.txt文件中）
	parameter	FILE_ADDR		=	"D:/FPGA_learning/Projects/08_ImageProcessing/03_simulation_platform_histogram_2/doc/hs/hs_pixel_cnt.txt";	// 统计结果文件保存位置
	// ******************************************************************************************
	
	
	// *******************************************端口声明***************************************
	// 系统信号
	input							pclk				;	// 像素时钟（pixel clock）
	input							rst_n				;	// 复位（reset）
	
	// 灰度直方图统计前的源视频信号
	input							src_hs_hsync		;	// 源视频 行同步信号（数据有效输出中标志）
	input							src_hs_vsync		;	// 源视频 场同步信号
	input		[SRC_HS_DW-1:0]		src_hs_data_out		;	// 源视频 像素数据输出
	
	// 灰度直方图统计后的统计结果
	input							hs_request			;	// 直方图统计结果 输出请求（一个时钟周期的脉冲）
	output	reg						hs_valid			;	// 直方图统计结果 有效输出中标志
	output	reg	[SRC_HS_DW-1:0]		hs_pixel			; 	// 直方图统计结果 当前像素值
	output		[HS_CNT_DW-1:0]		hs_pixel_cnt		; 	// 直方图统计结果 当前像素值像素点个数（顺序输出 像素值为0,1,...,255的个数）
	output	reg						result_rd_ready		;	// 直方图统计结果 读准备就绪标志（一个时钟周期的脉冲）（可作为 直方图统计结果 输出请求）
	output							result_wr_done		;	// 直方图统计结果 写入完成标志（一个时钟周期的脉冲）
	// *******************************************************************************************
	
	
	// ******************************************内部信号声明*************************************
	// 源视频像素数据输出打拍
	reg			[SRC_HS_DW-1:0]		src_hs_data_out_r1		;	// 源视频像素数据输出打1拍
	reg			[SRC_HS_DW-1:0]		src_hs_data_out_r2		;	// 源视频像素数据输出打2拍
	
	// 源视频行同步信号打拍
	reg								src_hs_hsync_r1			;	// 源视频行同步信号打1拍
	reg								src_hs_hsync_r2			;	// 源视频行同步信号打2拍
	
	// 源视频场同步信号打拍
	reg								src_hs_vsync_r1			;	// 源视频场同步信号打1拍
	
	// 源视频场同步信号边沿检测
	wire							src_hs_vsync_pos		;	// 源视频场同步信号上升沿
	wire							src_hs_vsync_neg		;	// 源视频场同步信号下降沿
	reg								src_hs_vsync_neg_r1		;	// 源视频场同步信号下降沿打1拍
	
	// 相同像素计数
	reg			[HS_CNT_DW-1:0]		cnt_same_pixel			;	// 对一帧图像的一行中，相邻的且相同的像素值进行个数计数
	
	// ---双口RAM：用于统计过程暂存
	// 统计计数
	wire							ramA_rd_en1				;	// A端口（设置为只读）读使能
	wire		[SRC_HS_DW-1:0]		ramA_rd_addr1			;	// A端口（设置为只读）读地址
	reg								ramB_wr_en1				;	// B端口（设置为只写）写使能
	wire		[SRC_HS_DW-1:0]		ramB_wr_addr1			;	// B端口（设置为只写）写地址
	wire		[HS_CNT_DW-1:0]		ramB_wr_data1			;	// B端口（设置为只写）写数据
	reg			[HS_CNT_DW-1:0]		ramB_wr_data1_pre		;	// B端口（设置为只写）写数据预备
	// 一帧的统计结果取出到另一个RAM中保存
	reg								ramA_rd_en2				;	// A端口（设置为只读）读使能
	reg			[SRC_HS_DW-1:0]		ramA_rd_addr2			;	// A端口（设置为只读）读地址
	// 一帧的统计结果清0，以统计新的一帧数据
	reg								ramB_wr_en2				;	// B端口（设置为只写）写使能
	reg			[SRC_HS_DW-1:0]		ramB_wr_addr2			;	// B端口（设置为只写）写地址
	wire		[HS_CNT_DW-1:0]		ramB_wr_data2			;	// B端口（设置为只写）写数据
	// 最终连接到统计过程暂存的双口RAM上的信号
	wire							ramA_rd_en				;	// A端口（设置为只读）读使能
	wire		[SRC_HS_DW-1:0]		ramA_rd_addr			;	// A端口（设置为只读）读地址
	wire		[HS_CNT_DW-1:0]		ramA_rd_data			;	// A端口（设置为只读）读数据
	wire							ramB_wr_en				;	// B端口（设置为只写）写使能
	wire		[SRC_HS_DW-1:0]		ramB_wr_addr			;	// B端口（设置为只写）写地址
	wire		[HS_CNT_DW-1:0]		ramB_wr_data			;	// B端口（设置为只写）写数据
	// ---
	
	// ---双口RAM：用于统计结果保存
	reg								result_ramA_rd_en		;	// A端口（设置为只读）读使能
	reg			[SRC_HS_DW-1:0]		result_ramA_rd_addr		;	// A端口（设置为只读）读地址
	wire		[HS_CNT_DW-1:0]		result_ramA_rd_data		;	// A端口（设置为只读）读数据
	reg								result_ramB_wr_en		;	// B端口（设置为只写）写使能
	reg			[SRC_HS_DW-1:0]		result_ramB_wr_addr		;	// B端口（设置为只写）写地址
	wire		[HS_CNT_DW-1:0]		result_ramB_wr_data		;	// B端口（设置为只写）写数据
	reg								result_ramB_wr_en_r1	;	// B端口（设置为只写）写使能 打1拍
	// ---
	
	// 直方图统计结果 输出请求有效期（只有在请求有效期发出的请求，才是有效的）
	reg								hs_request_valid_period	;
	
	// 调试参数
	integer							fid						;	// 文件指针
	reg								hs_valid_r1				;	// 直方图统计结果 有效输出中标志 打1拍
	wire							hs_result_store_begin	;	// 直方图统计结果存储到文件中的开始标志
	wire							hs_result_store_end		;	// 直方图统计结果存储到文件中的结束标志
	
	// *******************************************************************************************
	
	
	// *************************************源视频数据打拍****************************************
	
	// 源视频像素数据打拍
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
		begin
			src_hs_data_out_r1 <= 1'b0;
			src_hs_data_out_r2 <= 1'b0;
		end
		else
		begin
			src_hs_data_out_r1 <= src_hs_data_out;
			src_hs_data_out_r2 <= src_hs_data_out_r1;
		end
	end
	
	// 源视频行同步信号打拍
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
		begin
			src_hs_hsync_r1 <= 1'b0;
			src_hs_hsync_r2 <= 1'b0;
		end
		else
		begin
			src_hs_hsync_r1 <= src_hs_hsync;
			src_hs_hsync_r2 <= src_hs_hsync_r1;
		end
	end
	
	// 源视频场同步信号打拍
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
			src_hs_vsync_r1 <= 1'b0;
		else
			src_hs_vsync_r1 <= src_hs_vsync;
	end
	// *******************************************************************************************
	
	
	// *************************************源视频信号边沿检测************************************
	
	// 源视频场同步信号上升沿
	assign	src_hs_vsync_pos	=	~src_hs_vsync_r1 && src_hs_vsync	;	// 01
	
	// 源视频场同步信号下降沿
	assign	src_hs_vsync_neg	=	src_hs_vsync_r1 && ~src_hs_vsync	;	// 10
	
	// 源视频场同步信号下降沿打1拍
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
			src_hs_vsync_neg_r1 <= 1'b0;
		else
			src_hs_vsync_neg_r1 <= src_hs_vsync_neg;
	end
	// *******************************************************************************************
	
	
	// ************************************直方图统计过程计数*************************************
	
	// 相邻相同像素个数计数
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
			cnt_same_pixel <= 1'b0;
		else if(src_hs_hsync) // 行有效期间
		begin
			if(src_hs_data_out != src_hs_data_out_r1) // 当前像素值与上一拍像素值不同时，重新归1开始计数
				cnt_same_pixel <= 1'b1;
			else
				cnt_same_pixel <= cnt_same_pixel + 1'b1;
		end
		else
			cnt_same_pixel <= 1'b0;
	end
	
	// ---双口RAM的A端口（设置为只读）
	assign	ramA_rd_en1		=	src_hs_hsync		;	// 读使能：与 源视频行同步信号（数据有效输出中标志） 同步
	assign	ramA_rd_addr1	=	src_hs_data_out		;	// 读地址：与 源视频像素数据输出 同步
	// ---
	
	// ---双口RAM的B端口（设置为只写）
	// 写使能
	always @(*)
	begin
		// 读使能有效到数据读出会滞后1拍，写使能到写入数据给出是同步的，故写使能须比读使能滞后1拍
		// 且，只有相邻像素不同时才开始写入
		if(src_hs_hsync_r1 && src_hs_data_out_r1!=src_hs_data_out)
			ramB_wr_en1 <= 1'b1;
		else
			ramB_wr_en1 <= 1'b0;
	end
	// 写地址
	assign	ramB_wr_addr1	=	src_hs_data_out_r1	;	// 写地址：比 源视频像素数据输出 滞后1拍
	// 写数据
	always @(*)
	begin
		if(src_hs_hsync_r1) // 写数据预备：比 源视频行同步信号（数据有效输出中标志） 滞后1拍
			ramB_wr_data1_pre <= ramA_rd_data + cnt_same_pixel; // 写数据预备 = 读数据 + 相邻相同像素个数计数
		else
			ramB_wr_data1_pre <= 1'b0;
	end
	assign	ramB_wr_data1	=	(ramB_wr_en1) ? ramB_wr_data1_pre : 1'b0; // 写使能有效时，写数据预备就是写数据
	// ---
	// *******************************************************************************************
	
	
	// ************************************直方图统计暂存清0、取出********************************
	
	// ---直方图统计暂存结果清0（每帧开始时进行统计暂存清0，才能保证接下来的统计结果正确）
	// 写使能
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
			ramB_wr_en2 <= 1'b0;
		else if(src_hs_vsync_pos) // 场同步信号上升沿（一帧开始）时，先将统计结果清0，即 使能写使能
			ramB_wr_en2 <= 1'b1;
		else if(ramB_wr_addr2 == SRC_HS_DCNT-1'b1) // 清满255（所有8位像素的各像素值的个数）个时，清0完毕，即 不使能写使能
			ramB_wr_en2 <= 1'b0;
	end
	// 写地址
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
			ramB_wr_addr2 <= 1'b0;
		else if(ramB_wr_en2) // 写使能有效时，且未清完255个数据时，写地址递增
			ramB_wr_addr2 <= (ramB_wr_addr2>=SRC_HS_DCNT-1'b1) ? 1'b0 : ramB_wr_addr2+1'b1;
		else
			ramB_wr_addr2 <= 1'b0;
	end
	// 写数据
	assign	ramB_wr_data2	=	1'b0; // 将RAM内容清0，相当于往RAM中写入0
	// ---
	
	// ---直方图统计暂存结果取出（当前帧结束时将统计暂存结果读出，并写入统计结果保存RAM，才能保证在下一帧统计中上一帧的统计结果不丢失）
	// 读使能
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
			ramA_rd_en2 <= 1'b0;
		else if(src_hs_vsync_neg) // 场同步信号下降沿（一帧结束）时，开始取出统计结果，即 使能读使能
			ramA_rd_en2 <= 1'b1;
		else if(ramA_rd_addr2 == SRC_HS_DCNT-1'b1) // 取满255（所有8位像素的各像素值的个数）个时，取出完毕，即 不使能读使能
			ramA_rd_en2 <= 1'b0;
	end
	// 读地址
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
			ramA_rd_addr2 <= 1'b0;
		else if(ramA_rd_en2) // 读使能有效时，且未取完255个数据时，读地址递增
			ramA_rd_addr2 <= (ramA_rd_addr2>=SRC_HS_DCNT-1'b1) ? 1'b0 : ramA_rd_addr2+1'b1;
		else
			ramA_rd_addr2 <= 1'b0;
	end
	// ---
	// *******************************************************************************************
	
	
	// ********************************直方图统计过程双口RAM**************************************
	
	// 双口RAM的A端口（设置为只读）（行有效期间进行统计，场结束时读出统计暂存结果）
	assign	ramA_rd_en		=	src_hs_hsync ? ramA_rd_en1 : ramA_rd_en2		;
	assign	ramA_rd_addr	=	src_hs_hsync ? ramA_rd_addr1 : ramA_rd_addr2	;
	
	// 双口RAM的B端口（设置为只写）（行有效期间进行统计，场开始时进行清0）
	assign	ramB_wr_en		=	src_hs_hsync_r1 ? ramB_wr_en1 : ramB_wr_en2		;
	assign	ramB_wr_addr	=	src_hs_hsync_r1 ? ramB_wr_addr1 : ramB_wr_addr2	;
	assign	ramB_wr_data	=	src_hs_hsync_r1 ? ramB_wr_data1 : ramB_wr_data2	;
	
	// 双口RAM：用于统计过程暂存
	ram_2port ram_2port_u0(
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
	// *******************************************************************************************
	
	
	// ************************************直方图统计结果双口RAM**********************************
	
	// 统计结果从统计过程双口RAM中读出，并写入统计结果双口RAM中
	// 因为从 过程双口RAM读使能有效，到数据从RAM中读出，会有1拍的延时。
	// 故，若以 过程双口RAM读数据 为 结果双口RAM写数据 ，
	// 则须以 过程双口RAM读使能 打1拍 为 结果双口RAM写使能，
	// 以 过程双口RAM读地址 打1拍 为 结果双口RAM写地址，
	// 才能保证 结果双口RAM写使能、写地址、写数据 同步
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
		begin
			result_ramB_wr_addr <= 1'b0;
			result_ramB_wr_en <= 1'b0;
		end
		else
		begin
			result_ramB_wr_addr <= ramA_rd_addr2;
			result_ramB_wr_en <= ramA_rd_en2;
		end
	end
	assign	result_ramB_wr_data	=	ramA_rd_data		;
	
	// 统计结果写入保存完成标志（即 统计结果写入使能 下降沿）
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
			result_ramB_wr_en_r1 <= 1'b0;
		else
			result_ramB_wr_en_r1 <= result_ramB_wr_en;
	end
	assign	result_wr_done	=	result_ramB_wr_en_r1 && ~result_ramB_wr_en; // 10
	
	// 直方图统计结果 读准备就绪标志（即 统计结果写入使能 上升沿打一拍）
	// 因为 在IP核中已选择了 当对同一个地址通过不同端口同时进行读、写操作时，读操作先读出旧数据，写操作才写入新数据，
	// 所以，只要结果保存RAM中至少写入了一个数据之后（即 统计结果写入使能 上升沿打一拍），就可以对结果保存RAM进行数据读出了（即 直方图统计结果 读准备就绪）
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
			result_rd_ready <= 1'b0;
		else if(~result_ramB_wr_en_r1 & result_ramB_wr_en) // 01
			result_rd_ready <= 1'b1;
		else
			result_rd_ready <= 1'b0;
	end
	
	// 统计结果请求有效期
	// 起码要等至少写入一帧统计结果时，请求才有效
	// 而，统计结果是在场同步信号的下降沿的下一拍开始写入的
	// 所以，只有在第一次场同步信号的下降沿的下两拍后的请求，均为有效的
	// （在IP核中已选择了 当对同一个地址通过不同端口同时进行读、写操作时，读操作先读出旧数据，写操作才写入新数据）
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
			hs_request_valid_period <= 1'b0;
		else if(src_hs_vsync_neg_r1)
			hs_request_valid_period <= 1'b1;
		else
			hs_request_valid_period <= hs_request_valid_period;
	end
	
	// 统计结果双口RAM的读出使能
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
			result_ramA_rd_en <= 1'b0;
		else if(hs_request && hs_request_valid_period) // 只有在统计结果请求有效期的发出的请求，才有效
			result_ramA_rd_en <= 1'b1;
		else if(result_ramA_rd_addr == SRC_HS_DCNT-1'b1) // 读满255个时，读出结束
			result_ramA_rd_en <= 1'b0;
	end
	// 统计结果双口RAM的读出地址
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
			result_ramA_rd_addr <= 1'b0;
		else if(result_ramA_rd_en) // 读使能有效时，且未取完255个数据时，读地址递增
			result_ramA_rd_addr <= (result_ramA_rd_addr>=SRC_HS_DCNT-1'b1) ? 1'b0 : result_ramA_rd_addr+1'b1;
		else
			result_ramA_rd_addr <= 1'b0;
	end
	
	// 双口RAM：用于统计结果保存
	ram_2port ram_2port_u1(
		// 系统信号
		.clock				(pclk				),	// 同步时钟
		
		// A端口（可读可写，这里只作为读）
		.address_a			(result_ramA_rd_addr),
		.wren_a				(					),
		.data_a				(					),
		.rden_a				(result_ramA_rd_en	),
		.q_a				(result_ramA_rd_data),		
		
		// B端口（可读可写，这里只作为写）
		.address_b			(result_ramB_wr_addr),
		.wren_b				(result_ramB_wr_en	),
		.data_b				(result_ramB_wr_data),
		.rden_b				(					),
		.q_b				(					)
		);
	
	
	// ---统计结果有效输出中标志、统计结果当前像素、统计结果当前像素个数
	// 因为从 双口RAM读使能有效，到数据从RAM中读出，会有1拍的延时。
	// 故，若以 双口RAM读数据 为 统计结果当前像素个数 ，
	// 则须以 双口RAM读使能 打1拍 为 有效输出中标志，
	// 以 双口RAM读地址 打1拍 为 统计结果当前像素，
	// 才能保证 统计结果有效输出中标志、统计结果当前像素、统计结果当前像素个数 同步
	always @(posedge pclk, negedge rst_n)
	begin
		if(!rst_n)
		begin
			hs_valid <= 1'b0;
			hs_pixel <= 1'b0;
		end
		else
		begin
			hs_valid <= result_ramA_rd_en;
			hs_pixel <= result_ramA_rd_addr;
		end
	end
	assign	hs_pixel_cnt		=	result_ramA_rd_data	;
	// ---
	// *******************************************************************************************
	
	
	// *****************************将直方图存储到磁盘（写进.txt文件）****************************
	
	generate
	begin
		
		if(HS_RESULT_STORE) // 存储调试信号有效时，将直方图统计结果写入.txt文件
		begin: hs_store
			// 直方图统计结果 有效输出中标志 打1拍
			always @(posedge pclk, negedge rst_n)
			begin
				if(!rst_n)
					hs_valid_r1 <= 1'b0;
				else
					hs_valid_r1 <= hs_valid;
			end
			
			// 直方图统计结果存储到文件中的开始标志
			// hs_valid其实就是result_ramA_rd_en打1拍后的信号，
			// 因为要在开始标志的下一拍打开文件，所以要在 直方图统计结果有效输出中标志 上升沿的前一拍，将开始标志置1
			assign	hs_result_store_begin	=	~hs_valid && result_ramA_rd_en	;	// 01
			
			// 直方图统计结果存储到文件中的结束标志
			// 因为要在结束标志的下一拍关闭文件，所以要在 直方图统计结果有效输出中标志 下降沿，将结束标志置1
			assign	hs_result_store_end		=	hs_valid_r1 && ~hs_valid		;	// 10
			
			// 调试辅助信号有效时，将直方图统计结果写入.txt文件
			always @(posedge pclk, negedge rst_n)
			begin
				if(!rst_n)
					fid = 0;
				else if(hs_result_store_begin) // 打开文件
					fid = $fopen(FILE_ADDR, "w"); // 以只写的方式打开文本文件，文件不存在则创建
				else if(hs_valid) // 统计结果有效输出期间，将灰度直方图统计结果写入磁盘文件中
					$fdisplay(fid, "%d", hs_pixel_cnt);
				else if(hs_result_store_end) // 关闭文件
					$fclose(fid);
				else
					fid = 0;
			end
		end
		
	end
	endgenerate
	// *******************************************************************************************
	
endmodule

