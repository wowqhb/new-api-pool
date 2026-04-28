/*
Pool Management — 巡检 & 告警
- 立即巡检（异步触发）
- 告警历史列表（severity / resolved 过滤）
- Telegram 通道配置编辑（保存 + 测试发送）
*/

import React, { useEffect, useState } from 'react';
import {
  Card,
  Table,
  Button,
  Space,
  Tag,
  Modal,
  Form,
  Toast,
  Banner,
  Empty,
  Typography,
  Select,
  Switch,
  Popconfirm,
} from '@douyinfe/semi-ui';
import {
  IconRefresh,
  IconPlay,
  IconBell,
  IconSend,
} from '@douyinfe/semi-icons';
import { useTranslation } from 'react-i18next';
import { API } from '../../helpers/api';
import { showError, showSuccess } from '../../helpers';
import PoolPageLayout from './Layout';

const { Text } = Typography;

const SEVERITY_TAG = {
  info: { color: 'blue', text: '提示' },
  warning: { color: 'orange', text: '告警' },
  critical: { color: 'red', text: '严重' },
};

const Alerts = () => {
  const { t } = useTranslation();
  const [loading, setLoading] = useState(false);
  const [items, setItems] = useState([]);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(20);
  const [total, setTotal] = useState(0);
  const [openCount, setOpenCount] = useState(0);
  const [tgEnabled, setTgEnabled] = useState(false);
  const [filterSev, setFilterSev] = useState('');
  const [filterResolved, setFilterResolved] = useState('');

  const [tgModalVisible, setTgModalVisible] = useState(false);
  const [tgFormApi, setTgFormApi] = useState(null);
  const [tgConfig, setTgConfig] = useState({ token_masked: '', chat_id: '', enabled: false });

  const fetchData = async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams({
        p: String(page),
        page_size: String(pageSize),
      });
      if (filterSev) params.set('severity', filterSev);
      if (filterResolved) params.set('resolved', filterResolved);
      const res = await API.get(`/api/pool/alerts?${params.toString()}`);
      if (res?.data?.success) {
        const d = res.data.data;
        setItems(d.history?.items || []);
        setTotal(d.history?.total || 0);
        setOpenCount(d.open_count || 0);
        setTgEnabled(!!d.telegram_set);
      } else {
        showError(res?.data?.message || t('加载失败'));
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, pageSize]);

  const triggerHealthCheck = async () => {
    try {
      const res = await API.post('/api/pool/alerts/run', {});
      if (res?.data?.success) {
        showSuccess(t('巡检已在后台触发，几秒后可刷新查看结果'));
      } else {
        showError(res?.data?.message);
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    }
  };

  const resolveAlert = async (id) => {
    try {
      const res = await API.post(`/api/pool/alerts/${id}/resolve`, {});
      if (res?.data?.success) {
        showSuccess(t('已标记为已恢复'));
        fetchData();
      } else {
        showError(res?.data?.message);
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    }
  };

  const openTgModal = async () => {
    try {
      const res = await API.get('/api/pool/alerts/telegram');
      if (res?.data?.success) {
        setTgConfig(res.data.data);
        setTgModalVisible(true);
        setTimeout(() => {
          tgFormApi?.setValues({
            token: '',
            chat_id: res.data.data.chat_id || '',
          });
        }, 0);
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    }
  };

  const saveTg = async (values) => {
    try {
      const res = await API.put('/api/pool/alerts/telegram', values);
      if (res?.data?.success) {
        showSuccess(t('已保存'));
        setTgModalVisible(false);
        fetchData();
      } else {
        showError(res?.data?.message);
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    }
  };

  const testTg = async () => {
    try {
      const res = await API.post('/api/pool/alerts/telegram/test', {});
      if (res?.data?.success) {
        Modal.success({
          title: t('已成功发送测试消息'),
          content: t('请到 Telegram 中查收。如未收到，检查 Bot Token / Chat ID。'),
        });
      } else {
        Modal.error({
          title: t('Telegram 测试失败'),
          content: (
            <pre style={{ whiteSpace: 'pre-wrap', margin: 0 }}>
              {res?.data?.message || t('未知错误')}
            </pre>
          ),
          width: 560,
        });
      }
    } catch (e) {
      Modal.error({
        title: t('网络异常'),
        content: e?.message || '',
      });
    }
  };

  const columns = [
    { title: 'ID', dataIndex: 'id', width: 60 },
    {
      title: t('严重度'),
      dataIndex: 'severity',
      render: (v) => {
        const s = SEVERITY_TAG[v] || { color: 'grey', text: v };
        return <Tag color={s.color}>{s.text}</Tag>;
      },
    },
    {
      title: t('规则'),
      dataIndex: 'rule_key',
      render: (v) => <span className='font-mono text-xs'>{v}</span>,
    },
    { title: t('标题'), dataIndex: 'title' },
    {
      title: t('对象'),
      render: (_, r) => `${r.target_type || '-'}#${r.target_id || 0}`,
    },
    {
      title: t('已恢复'),
      dataIndex: 'resolved',
      render: (v) =>
        v ? (
          <Tag color='green'>{t('已恢复')}</Tag>
        ) : (
          <Tag color='red'>{t('未恢复')}</Tag>
        ),
    },
    {
      title: t('时间'),
      dataIndex: 'created_time',
      render: (v) => (v ? new Date(v * 1000).toLocaleString() : '-'),
    },
    {
      title: t('操作'),
      render: (_, r) =>
        !r.resolved && (
          <Popconfirm
            title={t('确认标记为已恢复？')}
            onConfirm={() => resolveAlert(r.id)}
          >
            <Button size='small'>{t('恢复')}</Button>
          </Popconfirm>
        ),
    },
  ];

  return (
    <PoolPageLayout
      title={t('巡检 & 告警')}
      subtitle={t('每 5 分钟自动巡检；可手动触发并配置 Telegram 推送')}
      badge='Alerts'
      extra={
        <Space>
          <Button icon={<IconRefresh />} size='small' onClick={fetchData}>
            {t('刷新')}
          </Button>
          <Button
            icon={<IconPlay />}
            type='primary'
            theme='light'
            size='small'
            onClick={triggerHealthCheck}
          >
            {t('立即巡检')}
          </Button>
          <Button
            icon={<IconBell />}
            type='primary'
            theme='solid'
            size='small'
            onClick={openTgModal}
          >
            {t('Telegram 配置')}
          </Button>
        </Space>
      }
    >
      <div className='mb-3 grid gap-3 md:grid-cols-3'>
        <Card bodyStyle={{ padding: 14 }}>
          <Text type='tertiary' size='small'>
            {t('未恢复告警')}
          </Text>
          <div
            className='mt-1'
            style={{
              fontSize: 22,
              fontWeight: 600,
              color:
                openCount === 0
                  ? 'var(--semi-color-success)'
                  : 'var(--semi-color-danger)',
            }}
          >
            {openCount}
          </div>
        </Card>
        <Card bodyStyle={{ padding: 14 }}>
          <Text type='tertiary' size='small'>
            Telegram 通道
          </Text>
          <div className='mt-1' style={{ fontSize: 14 }}>
            {tgEnabled ? (
              <Tag color='green'>{t('已配置')}</Tag>
            ) : (
              <Tag color='orange'>{t('未配置')}</Tag>
            )}
          </div>
        </Card>
        <Card bodyStyle={{ padding: 14 }}>
          <Text type='tertiary' size='small'>
            {t('巡检间隔')}
          </Text>
          <div className='mt-1' style={{ fontSize: 14 }}>
            {t('每 5 分钟（默认）')}
          </div>
        </Card>
      </div>

      <Space className='mb-3'>
        <Select
          placeholder={t('严重度')}
          value={filterSev}
          onChange={(v) => setFilterSev(v || '')}
          optionList={[
            { label: t('全部'), value: '' },
            { label: SEVERITY_TAG.info.text, value: 'info' },
            { label: SEVERITY_TAG.warning.text, value: 'warning' },
            { label: SEVERITY_TAG.critical.text, value: 'critical' },
          ]}
          style={{ width: 140 }}
        />
        <Select
          placeholder={t('恢复状态')}
          value={filterResolved}
          onChange={(v) => setFilterResolved(v || '')}
          optionList={[
            { label: t('全部'), value: '' },
            { label: t('已恢复'), value: 'true' },
            { label: t('未恢复'), value: 'false' },
          ]}
          style={{ width: 140 }}
        />
        <Button
          onClick={() => {
            setPage(1);
            fetchData();
          }}
        >
          {t('应用过滤')}
        </Button>
      </Space>

      {items.length === 0 ? (
        <Empty description={t('近期暂无告警，系统运行良好')} />
      ) : (
        <Table
          loading={loading}
          dataSource={items}
          columns={columns}
          rowKey='id'
          pagination={{
            currentPage: page,
            pageSize,
            total,
            onPageChange: setPage,
            onPageSizeChange: setPageSize,
            showSizeChanger: true,
          }}
        />
      )}

      <Modal
        title={t('Telegram 通道配置')}
        visible={tgModalVisible}
        onCancel={() => setTgModalVisible(false)}
        footer={null}
        width={520}
      >
        <Banner
          type='info'
          description={t(
            '在 BotFather 创建 bot 获取 Token；用 @userinfobot 获取 Chat ID（自己的或群组）。',
          )}
          closeIcon={null}
          className='mb-3'
        />
        <Form
          getFormApi={setTgFormApi}
          onSubmit={saveTg}
          labelPosition='left'
          labelWidth={100}
        >
          <Form.Input
            field='token'
            label='Bot Token'
            placeholder={
              tgConfig.token_masked
                ? `${t('当前')}: ${tgConfig.token_masked}（留空保留）`
                : t('从 BotFather 获取')
            }
          />
          <Form.Input
            field='chat_id'
            label='Chat ID'
            placeholder='123456789 / -1001234567'
          />
          <div className='mt-3 flex items-center justify-between'>
            <Button
              icon={<IconSend />}
              onClick={testTg}
              disabled={!tgEnabled}
            >
              {t('发送测试消息')}
            </Button>
            <Space>
              <Button onClick={() => setTgModalVisible(false)}>
                {t('取消')}
              </Button>
              <Button type='primary' theme='solid' htmlType='submit'>
                {t('保存')}
              </Button>
            </Space>
          </div>
        </Form>
      </Modal>
    </PoolPageLayout>
  );
};

export default Alerts;
