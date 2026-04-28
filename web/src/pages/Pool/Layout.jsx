/*
Pool Management — 共用页面壳（标题 + 副标题 + Tag + 内容容器）
保持与 new-api 现有页面 (mt-[60px] px-2) 视觉间距一致，并使用 Semi UI Typography/Tag。
*/

import React from 'react';
import { Typography, Tag, Space } from '@douyinfe/semi-ui';
import { useTranslation } from 'react-i18next';

const { Title, Text } = Typography;

const PoolPageLayout = ({ title, subtitle, badge = '', children, extra = null }) => {
  const { t } = useTranslation();
  return (
    <div className='mt-[60px] px-4 pb-8'>
      <div className='flex items-start justify-between mb-5'>
        <div>
          <Space align='center'>
            <Title heading={4} style={{ margin: 0 }}>
              {title}
            </Title>
            {badge && (
              <Tag color='violet' size='small' shape='circle'>
                {badge}
              </Tag>
            )}
          </Space>
          {subtitle && (
            <div className='mt-1'>
              <Text type='tertiary' size='small'>
                {subtitle}
              </Text>
            </div>
          )}
        </div>
        <div>{extra}</div>
      </div>
      {children}
    </div>
  );
};

export default PoolPageLayout;
