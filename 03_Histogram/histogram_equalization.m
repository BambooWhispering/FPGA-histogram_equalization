% �Ҷ�ֱ��ͼ���⻯ͳ��
clear;
clc;

% ---��ȡԴͼ���ļ�
% ��ȡͼ���ļ���ͼ������
img = imread('./img_src/img.jpeg');

% ---��ȡԴͼ���ļ�����Ϣ
% ��ȡͼ��������������ͨ����
[num_row, num_col, num_channel] = size(img);

% ��ȡͼ��RGB����ͨ����ͼ��
R = img(:, :, 1); % Rͨ��
G = img(:, :, 2); % Gͨ��
B = img(:, :, 3); % Bͨ��

% �� ���������� ��ŵ�ͼ���ļ�ת��Ϊ ������������
% ��Ϊmatlab�У������һά�����ǰ���һ��һ�з��ʵģ������ǰ���һ��һ�з��ʵ�
R1 = R';
G1 = G';
B1 = B';

% ---����ģ������ͷ��Ƶ֡��RGB��ͨ�����ı��ļ���R1��G1��B1�� R2��G2��B2�� ...��
% ÿ3������Ϊһ���������ݵ�RGBת�þ���
RGB1 = zeros(num_col*3, num_row, 'uint8');
for i=1:1:num_row*num_col*3
    if mod(i, 3)==1
        RGB1(i) = R1(floor((i-1)/3) + 1); % floor����ȡ�����൱�ڽضϣ�+1����Ϊmatlab���������Ǵ�1��ʼ�Ķ�����0
    elseif mod(i, 3)==2
        RGB1(i) = G1(floor((i-1)/3) + 1);
    else
        RGB1(i) = B1(floor((i-1)/3) + 1);
    end
end
fid_rgb = fopen('./img_src/img.txt', 'wt'); % ��д�ķ�ʽ���ļ����ļ��������򴴽�
fprintf(fid_rgb, '%d\n', RGB1); % ��������ʽ����RGB��ͨ��ͼ�����RGB1�������д�룩fid_rgb�����ָ����ļ���'img_rgb.txt'���У�ÿ���һ�����ݾͻ�һ����
fclose(fid_rgb); % �ر��ļ�

% ---���ɵ�ͨ���Ҷ�ͼ����ı��ļ�
% ��ͨ���Ҷ�ͼ��
gray = rgb2gray(img);
gray1 = gray';
fid_gray = fopen('./img_src/img_gray.txt', 'wt'); % ��д�ķ�ʽ���ļ����ļ��������򴴽�
fprintf(fid_gray, '%d\n', gray1); % ��������ʽ�����Ҷ�ͼ�����gray1�������д�룩fid_gray�����ָ����ļ���'img_gray.txt'���У�ÿ���һ�����ݾͻ�һ����
fclose(fid_gray); % �ر��ļ�

% ---���ɻҶ�ͼ���ͼ���ļ�
% ��ͼ��д�뵽���̣�image write��
imwrite(gray, './img_src/img_gray.jpeg'); % ͼ������Ҫд��Ĵ���·��

% �Ҷ�ֱ��ͼ���⻯ǰ��ֱ��ͼͳ��
[gray_pixel_cnt, gray_pixel] = imhist(gray);
figure;
title('���⻯ǰ�ĻҶ�ֱ��ͼ');
imhist(gray);

% matlab�Ҷ�ֱ��ͼ���⻯���ֱ��ͼͳ��
img_dst_gray_matlab = histeq(gray, 256);
imwrite(img_dst_gray_matlab, './img_dst_gray/img_gray_matlab.jpeg'); % ͼ������Ҫд��Ĵ���·��
[dst_pixel_cnt, dst_pixel] = imhist(img_dst_gray_matlab);
figure;
title('matlab���⻯��ĻҶ�ֱ��ͼ');
imhist(img_dst_gray_matlab);

